{
  lib,
  pkgs,
  commonConfig,
  deploymentFiles,
}: {...}: {
  imports = [
    (commonConfig.vm)
  ];

  # Standalone K3s server configuration
  networking = {
    hostName = "k3s-server";

    # Static IP configuration
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "10.0.2.15";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "10.0.2.2";
  };

  # Ensure SSH is properly configured for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Set root password for SSH access
  users.users.root.initialPassword = "nixos";

  # K3s standalone server configuration
  services.k3s = {
    enable = true;
    role = "server";
    # No serverAddr needed for standalone setup
    extraFlags = [
      # Server specific flags
      "--write-kubeconfig-mode=0644"
      "--disable=traefik" # We'll deploy our own ingress
      "--node-ip=10.0.2.15" # Use the static IP we defined above
      "--tls-san=10.0.2.15" # Add IP to the TLS SAN
      "--tls-san=k3s-server" # Add hostname to the TLS SAN
    ];
  };

  # Enhanced script to copy and modify kubeconfig for external use
  systemd.services.copy-kubeconfig = {
    description = "Export kubeconfig to shared folder for k9s";
    after = ["k3s.service" "network.target"];
    requires = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [k3s coreutils jq iproute2 gnugrep];
    script = ''
      # Sleep to ensure k3s is fully initialized
      sleep 10

      # Ensure shared directory exists and is accessible
      mkdir -p /shared
      chmod 777 /shared

      # Copy kubeconfig
      if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        # Use the static IP defined in networking configuration
        VM_IP="10.0.2.15"

        echo "Using VM IP: $VM_IP"

        # Create a temporary file first and then move it to avoid partial writes
        cat /etc/rancher/k3s/k3s.yaml | \
          sed "s|127.0.0.1|$VM_IP|g" | \
          sed "s|localhost|$VM_IP|g" | \
          sed "s|https://k3s-server:6443|https://$VM_IP:6443|g" > /shared/kubeconfig.tmp

        # Make it readable and move into place
        chmod 644 /shared/kubeconfig.tmp
        mv /shared/kubeconfig.tmp /shared/kubeconfig

        echo "Kubeconfig successfully exported to /shared/kubeconfig with IP $VM_IP"
        echo "Debug: Contents of /shared directory:"
        ls -la /shared/
      else
        echo "K3s kubeconfig not found yet at /etc/rancher/k3s/k3s.yaml"
        ls -la /etc/rancher/k3s/ || echo "Directory not accessible"
        exit 1
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "15s";
      StandardOutput = "journal+console";
    };
  };

  # Create a timer to periodically update the kubeconfig
  systemd.timers.copy-kubeconfig = {
    description = "Timer for updating kubeconfig in shared folder";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "45s"; # Wait longer for k3s and networking to be fully ready
      OnUnitActiveSec = "3min";
      Unit = "copy-kubeconfig.service";
    };
  };

  # Apply Kubernetes deployments after setup
  systemd.services.k3s-deploy = {
    description = "Apply Kubernetes deployments";
    after = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [k3s];
    script = ''
      # Wait for k3s to be ready
      sleep 30

      # Apply deployments
      k3s kubectl apply -f /etc/k3s/deployments/database.yaml
      k3s kubectl apply -f /etc/k3s/deployments/nginx.yaml

      echo "Kubernetes deployments applied"
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  # Copy deployment files to VM - using proper paths from flake
  environment.etc."k3s/deployments/database.yaml".source = deploymentFiles.database;
  environment.etc."k3s/deployments/nginx.yaml".source = deploymentFiles.nginx;
}
