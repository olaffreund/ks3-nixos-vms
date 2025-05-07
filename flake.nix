{
  description = "K3s cluster with 3 NixOS VMs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;

    # Common VM configuration
    commonConfig = import ./cluster/default.nix {inherit lib;};

    # VM definitions
    vmMaster = import ./cluster/master.nix {
      inherit lib pkgs commonConfig;
    };

    vmWorker1 = import ./cluster/worker1.nix {
      inherit lib pkgs commonConfig;
    };

    vmWorker2 = import ./cluster/worker2.nix {
      inherit lib pkgs commonConfig;
    };
  in {
    nixosConfigurations = {
      # Master node
      master = lib.nixosSystem {
        inherit system;
        modules = [vmMaster];
      };

      # Worker nodes
      worker1 = lib.nixosSystem {
        inherit system;
        modules = [vmWorker1];
      };

      worker2 = lib.nixosSystem {
        inherit system;
        modules = [vmWorker2];
      };
    };

    # Packages to build the VMs
    packages.${system} = {
      master = self.nixosConfigurations.master.config.system.build.vm;
      worker1 = self.nixosConfigurations.worker1.config.system.build.vm;
      worker2 = self.nixosConfigurations.worker2.config.system.build.vm;

      # Meta package to build and run all VMs
      default = pkgs.writeShellScriptBin "run-cluster" ''
        #!/bin/sh
        # Start all VMs
        echo "Starting K3s cluster VMs..."
        ${self.packages.${system}.master}/bin/run-nixos-vm &
        sleep 10
        ${self.packages.${system}.worker1}/bin/run-nixos-vm &
        ${self.packages.${system}.worker2}/bin/run-nixos-vm &
        wait
      '';
    };
  };
}
