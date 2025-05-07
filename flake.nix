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

    # Deployment files as derivations
    deploymentFiles = {
      database = builtins.path {
        name = "database-config";
        path = ./deployment/database.yaml;
      };
      nginx = builtins.path {
        name = "nginx-config";
        path = ./deployment/nginx.yaml;
      };
    };

    # Common VM configuration
    commonConfig = import ./cluster/default.nix {inherit lib;};

    # VM definitions
    vmMaster = import ./cluster/master.nix {
      inherit lib pkgs commonConfig deploymentFiles;
    };

    vmWorker1 = import ./cluster/worker1.nix {
      inherit lib pkgs commonConfig;
    };

    vmWorker2 = import ./cluster/worker2.nix {
      inherit lib pkgs commonConfig;
    };

    # NixOS configurations
    nixosConfigurations = {
      # Master node
      master = lib.nixosSystem {
        inherit system;
        modules = [vmMaster];
        specialArgs = {inherit deploymentFiles;};
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

    # Simpler approach - just use the VM directly
    mkQemuImage = name: nixosConfig: nixosConfig.config.system.build.vm;

    # Remote build script
    remoteBuildScript = target:
      pkgs.writeShellScriptBin "build-remote" ''
        #!/bin/sh
        echo "Building K3s cluster VMs on ${target}..."
        nix build .#master .#worker1 .#worker2 --builders "ssh://${target}" --max-jobs 4
        echo "Build complete."
      '';

    # Zellij launch script for K3s cluster
    zellijLaunchScript = pkgs.writeShellScriptBin "k3s-cluster-zellij" ''
      #!/bin/sh
      # Ensure shared directory exists
      mkdir -p /tmp/nixos-vm-shared

      # Launch zellij with K3s cluster layout
      echo "Starting K3s cluster management environment in Zellij..."
      ${pkgs.zellij}/bin/zellij --layout ${./config/k3s-cluster.kdl}
    '';
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        # Regular VM packages
        master = nixosConfigurations.master.config.system.build.vm;
        worker1 = nixosConfigurations.worker1.config.system.build.vm;
        worker2 = nixosConfigurations.worker2.config.system.build.vm;

        # QEMU images as top-level packages with simple names
        "qemu-master" = mkQemuImage "master" nixosConfigurations.master;
        "qemu-worker1" = mkQemuImage "worker1" nixosConfigurations.worker1;
        "qemu-worker2" = mkQemuImage "worker2" nixosConfigurations.worker2;

        # All QEMU images
        "qemu-images-all" = pkgs.symlinkJoin {
          name = "all-qemu-images";
          paths = [
            (mkQemuImage "master" nixosConfigurations.master)
            (mkQemuImage "worker1" nixosConfigurations.worker1)
            (mkQemuImage "worker2" nixosConfigurations.worker2)
          ];
        };

        # Remote build helpers
        "build-remote-local" = remoteBuildScript "localhost";
        "build-remote-server" = remoteBuildScript "build-server.example.com";

        # Zellij K3s cluster launch script
        "k3s-cluster-zellij" = zellijLaunchScript;

        # Meta package to build and run all VMs
        default = pkgs.writeShellScriptBin "run-cluster" ''
          #!/bin/sh
          # Start all VMs
          echo "Starting K3s cluster VMs..."
          $${nixosConfigurations.master.config.system.build.vm}/bin/run-nixos-vm &
          sleep 10
          $${nixosConfigurations.worker1.config.system.build.vm}/bin/run-nixos-vm &
          $${nixosConfigurations.worker2.config.system.build.vm}/bin/run-nixos-vm &
          wait
        '';
      };

      # Development shell
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Kubernetes tools
          kubectl
          k3s
          kubernetes-helm

          # VM management
          qemu
          libguestfs # For manipulating VM disk images

          # Network tools
          tailscale

          # Deployment tools
          kustomize

          # Development tools
          nixpkgs-fmt # For formatting Nix files
          git

          # Terminal multiplexer and shell
          zellij
          zsh
          direnv # For .envrc support

          # Include our custom scripts
          self.packages.${system}.default
          self.packages.${system}."build-remote-local"
          self.packages.${system}."build-remote-server"
          self.packages.${system}."k3s-cluster-zellij"
        ];

        shellHook = ''
          echo "K3s NixOS VM Development Environment"
          echo "------------------------------------"
          echo "Available tools:"
          echo " - kubectl: Kubernetes command-line tool"
          echo " - k3s: Lightweight Kubernetes"
          echo " - helm: Kubernetes package manager"
          echo " - qemu: VM virtualization"
          echo " - tailscale: Secure networking"
          echo " - kustomize: Kubernetes configuration management"
          echo " - zellij: Terminal multiplexer"
          echo " - zsh: Default shell"
          echo " - direnv: Environment management"
          echo ""
          echo "VM Management Commands:"
          echo " - run-cluster: Run all VMs locally"
          echo " - nix build .#qemu-master: Build master QEMU image"
          echo " - nix build .#qemu-worker1: Build worker1 QEMU image"
          echo " - nix build .#qemu-worker2: Build worker2 QEMU image"
          echo " - nix build .#qemu-images-all: Build all QEMU images"
          echo ""
          echo "Remote Build Commands:"
          echo " - build-remote: Build all QEMU images on configured remote builder"
          echo " - nix build .#qemu-images-all --builders 'ssh://your-remote': Manual remote build"
          echo ""
          echo "K3s Cluster in Zellij Command:"
          echo " - k3s-cluster-zellij: Launch the K3s cluster in a Zellij session with interactive panes"
          echo ""
          echo "Environment Management:"
          echo " - direnv is enabled - the .envrc file will automatically load the development environment"
          echo " - Default shell set to zsh for improved interactive experience"
          echo ""
          echo "To access kubeconfig: export KUBECONFIG=/tmp/nixos-vm-shared/kubeconfig"

          # Create a helper function for building QEMU images
          build_qemu_image() {
            local NODE_TYPE=$1
            echo "Building QEMU image for $NODE_TYPE node..."
            nix build .#qemu-$NODE_TYPE
            echo "Image built at ./result/bin/run-$NODE_TYPE-vm"
          }

          # Export the function
          export -f build_qemu_image

          echo ""
          echo "Helper commands added to your shell:"
          echo " - build_qemu_image master: Build QEMU image for master node"
          echo " - build_qemu_image worker1: Build QEMU image for worker1 node"
          echo " - build_qemu_image worker2: Build QEMU image for worker2 node"

          echo ""
          echo "To start the K3s cluster in Zellij, run: k3s-cluster-zellij"
        '';
      };
    })
    // {
      # Top-level outputs that don't vary by system
      inherit nixosConfigurations;
    };
}
