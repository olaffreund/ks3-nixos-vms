{lib, ...}: {
  # Common VM configuration
  vm = {pkgs, ...}: {
    # Basic system configuration
    system.stateVersion = "25.05";

    # VM settings
    virtualisation = {
      # Empty virtualisation block, options moved to vmVariant
    };

    # For NixOS VM testing, use these options instead
    virtualisation.vmVariant = {
      virtualisation = {
        cores = 2;
        memorySize = 2048;

        # Shared folder for easy file exchange with host
        sharedDirectories = {
          shared = {
            source = lib.mkForce "/tmp/nixos-vm-shared";
            target = lib.mkForce "/shared";
          };
        };
      };
    };

    # Required file systems configuration
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
    };

    # Boot loader configuration
    boot.loader.grub = {
      enable = true;
      devices = ["/dev/sda"];
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
