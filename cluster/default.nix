{lib, ...}: {
  # Common VM configuration
  vm = {pkgs, ...}: {
    # Basic system configuration
    system.stateVersion = "25.05";

    # Enable IP forwarding
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

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

      # Explicitly configure the shared 9p mount
      "/shared" = {
        device = "shared";
        fsType = "9p";
        options = ["trans=virtio" "version=9p2000.L" "msize=1048576" "cache=loose"];
        neededForBoot = false;
        depends = [];
      };
    };

    # Boot loader configuration
    boot.loader.grub = {
      enable = true;
      devices = ["/dev/sda"];
    };

    # Simplified network configuration
    networking = {
      firewall = {
        enable = false;
        allowedTCPPorts = [22 80 443 6443];
      };

      # Common DNS settings
      nameservers = ["8.8.8.8" "1.1.1.1"];

      # Simple hosts configuration for standalone server
      hosts = {
        "127.0.0.1" = ["localhost"];
        "::1" = ["localhost"];
        "10.0.2.15" = ["k3s-server" "k3s-server.local"];
      };
    };

    # Base packages
    environment.systemPackages = with pkgs; [
      wget
      curl
      vim
      git
      htop
      k3s
      k9s
      # Add basic network tools
      inetutils
      dnsutils
      # Add polkit-related packages
      polkit
      polkit_gnome
      libsForQt5.polkit-kde-agent
      # Terminal-compatible polkit agent
      lxqt.lxqt-policykit
    ];

    # Enable polkit service with headless configuration
    security.polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';
    };

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
  };
}
