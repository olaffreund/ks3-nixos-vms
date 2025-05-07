{
  lib,
  pkgs,
  commonConfig,
}: {config, ...}: {
  imports = [
    (commonConfig.vm)
  ];

  # Master specific configuration
  networking.hostName = "k3s-master";

  # K3s server (master) configuration
  services.k3s = {
    enable = true;
    role = "server";
    serverAddr = "https://k3s-master:6443";
    token = "my-shared-secret-token"; # In real setup, use a more secure token
    extraFlags = toString [
      # Server specific flags
      "--cluster-init"
      "--disable=traefik" # We'll deploy our own ingress
      "--tls-san=k3s-master"
      "--node-ip=$(hostname -I | awk '{print $1}')"
    ];
  };

  # Ensure k3s data is persisted
  systemd.services.k3s.after = ["tailscale.service"];

  # Script to copy kubeconfig to shared folder for convenience
  systemd.services.copy-kubeconfig = {
    description = "Copy kubeconfig to shared folder";
    after = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    script = ''
      mkdir -p /shared
      cp /etc/rancher/k3s/k3s.yaml /shared/kubeconfig
      chmod 644 /shared/kubeconfig
      echo "Kubeconfig copied to /shared/kubeconfig"
    '';
    serviceConfig = {
      Type = "oneshot";
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

  # Copy deployment files to VM
  environment.etc."k3s/deployments/database.yaml".source = ../deployment/database.yaml;
  environment.etc."k3s/deployments/nginx.yaml".source = ../deployment/nginx.yaml;

  # Tailscale setup for master - auto authenticate if a key is provided
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = ["network-pre.target" "tailscale.service"];
    wants = ["network-pre.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      # Wait for tailscaled to settle
      sleep 2

      # Check if we are already authenticated to tailscale
      status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then
        exit 0
      fi

      # Otherwise authenticate with tailscale
      # In production, use tailscale auth key from a file or environment variable
      ${pkgs.tailscale}/bin/tailscale up --authkey=YOUR_TAILSCALE_AUTH_KEY --hostname="k3s-master"
    '';
  };
}
