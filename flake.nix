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

    # NixOS configurations
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

    # Function to create a QEMU disk image for a VM
    mkQemuImage = name: nixosConfig:
      pkgs.vmTools.runInLinuxVM (
        pkgs.runCommand "qemu-image-${name}" {
          memSize = 1024;
          diskImage = pkgs.vmTools.makeEmptyImage {
            size = 10240; # 10GB disk image
            format = "qcow2";
            name = "${name}.qcow2";
          };
          buildInputs = with pkgs; [nixos-install-tools util-linux e2fsprogs];
        } ''
          # Format the disk
          mkfs.ext4 -L nixos /dev/sda
          mkdir -p /mnt
          mount /dev/sda /mnt

          # Install NixOS
          nixos-install --root /mnt --system ${nixosConfig.config.system.build.toplevel} --no-bootloader

          # Unmount and copy the image
          umount /mnt
          mkdir -p $out
          cp "$diskImage" "$out/${name}.qcow2"
        ''
      );

    # Remote build script
    remoteBuildScript = target:
      pkgs.writeShellScriptBin "build-remote" ''
        #!/bin/sh
        echo "Building K3s cluster QEMU images on ${target}..."
        nix build .#qemuImages.master .#qemuImages.worker1 .#qemuImages.worker2 --builders "ssh://${target}" --max-jobs 4
        echo "Build complete. Images are available in ./result*/master.qcow2, etc."
      '';

    # Per-system packages
    systemPackages = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # Regular VM packages
      master = nixosConfigurations.master.config.system.build.vm;
      worker1 = nixosConfigurations.worker1.config.system.build.vm;
      worker2 = nixosConfigurations.worker2.config.system.build.vm;

      # QEMU disk images
      qemuImages = {
        master = mkQemuImage "master" nixosConfigurations.master;
        worker1 = mkQemuImage "worker1" nixosConfigurations.worker1;
        worker2 = mkQemuImage "worker2" nixosConfigurations.worker2;

        # Build all images at once
        all = pkgs.symlinkJoin {
          name = "all-qemu-images";
          paths = [
            (mkQemuImage "master" nixosConfigurations.master)
            (mkQemuImage "worker1" nixosConfigurations.worker1)
            (mkQemuImage "worker2" nixosConfigurations.worker2)
          ];
        };
      };

      # Remote build helpers
      remoteBuild = {
        # Add your typical remote build targets here
        localMachine = remoteBuildScript "localhost";
        buildServer = remoteBuildScript "build-server.example.com";
      };

      # Meta package to build and run all VMs
      default = pkgs.writeShellScriptBin "run-cluster" ''
        #!/bin/sh
        # Start all VMs
        echo "Starting K3s cluster VMs..."
        ${nixosConfigurations.master.config.system.build.vm}/bin/run-nixos-vm &
        sleep 10
        ${nixosConfigurations.worker1.config.system.build.vm}/bin/run-nixos-vm &
        ${nixosConfigurations.worker2.config.system.build.vm}/bin/run-nixos-vm &
        wait
      '';
    };

    # Per-system dev shells
    systemDevShells = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages = systemPackages system;
    in {
      default = pkgs.mkShell {
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

          # Include our custom scripts
          packages.default
          packages.remoteBuild.localMachine
          packages.remoteBuild.buildServer
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
          echo ""
          echo "VM Management Commands:"
          echo " - run-cluster: Run all VMs locally"
          echo " - nix build .#qemuImages.master: Build master QEMU image"
          echo " - nix build .#qemuImages.worker1: Build worker1 QEMU image"
          echo " - nix build .#qemuImages.worker2: Build worker2 QEMU image"
          echo " - nix build .#qemuImages.all: Build all QEMU images"
          echo ""
          echo "Remote Build Commands:"
          echo " - build-remote: Build all QEMU images on configured remote builder"
          echo " - nix build .#qemuImages.all --builders 'ssh://your-remote': Manual remote build"
          echo ""
          echo "To access kubeconfig: export KUBECONFIG=/tmp/nixos-vm-shared/kubeconfig"

          # Create a helper function for building QEMU images
          build_qemu_image() {
            local NODE_TYPE=$1
            echo "Building QEMU image for $NODE_TYPE node..."
            nix build .#qemuImages.$NODE_TYPE
            echo "Image built at ./result/$NODE_TYPE.qcow2"
          }

          # Export the function
          export -f build_qemu_image

          echo ""
          echo "Helper commands added to your shell:"
          echo " - build_qemu_image master: Build QEMU image for master node"
          echo " - build_qemu_image worker1: Build QEMU image for worker1 node"
          echo " - build_qemu_image worker2: Build QEMU image for worker2 node"
        '';
      };
    };
  in {
    inherit nixosConfigurations;

    # Use flake-utils to generate outputs for each system
    packages = flake-utils.lib.eachDefaultSystem (system: systemPackages system);
    devShells = flake-utils.lib.eachDefaultSystem (system: systemDevShells system);
  };
}
