{lib}: {
  # Common VM configuration
  vm = {
    config,
    pkgs,
    ...
  }: {
    # Basic system configuration
    system.stateVersion = "23.11";

    # VM settings
    virtualisation = {
      memorySize = 2048; # 2GB RAM
      cores = 2; # 2 CPU cores

      # Shared folder for easy file exchange with host
      sharedDirectories = {
        shared = {
          source = "/tmp/nixos-vm-shared";
          target = "/shared";
        };
      };
    };

    # Network configuration
    networking = {
      firewall.enable = true;
      firewall.allowedTCPPorts = [22 80 443 6443];
      useDHCP = true;
    };

    # Base packages
    environment.systemPackages = with pkgs; [
      wget
      curl
      vim
      git
      htop
      k3s
      tailscale
    ];

    # SSH server
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
      };
    };

    # User configuration
    users.users.root.initialPassword = "nixos";
    users.users.nixos = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      initialPassword = "nixos";
    };

    # Tailscale configuration
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };
  };
}
