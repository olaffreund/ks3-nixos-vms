{
  lib,
  pkgs,
  commonConfig,
}: {config, ...}: {
  imports = [
    (commonConfig.vm)
  ];

  # Worker specific configuration
  networking.hostName = "k3s-worker1";

  # K3s agent (worker) configuration
  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://k3s-master:6443";
    token = "my-shared-secret-token"; # Must match the server token
    extraFlags = toString [
      # Agent specific flags
      "--node-ip=$(hostname -I | awk '{print $1}')"
    ];
  };

  # Ensure k3s starts after tailscale
  systemd.services.k3s.after = ["tailscale.service"];

  # Tailscale setup for worker
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
      ${pkgs.tailscale}/bin/tailscale up --authkey=YOUR_TAILSCALE_AUTH_KEY --hostname="k3s-worker1"
    '';
  };
}
