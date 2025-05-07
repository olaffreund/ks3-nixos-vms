{
  description = "Standalone K3s NixOS VM";

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

    # VM definition
    vmMaster = import ./cluster/master.nix {
      inherit lib pkgs commonConfig deploymentFiles;
    };

    # NixOS configurations
    nixosConfigurations = {
      # Master node (standalone)
      master = lib.nixosSystem {
        inherit system;
        modules = [vmMaster];
        specialArgs = {inherit deploymentFiles;};
      };
    };

    # Create QEMU image
    mkQemuImage = name: nixosConfig: nixosConfig.config.system.build.vm;

    # Remote build script
    remoteBuildScript = target:
      pkgs.writeShellScriptBin "build-remote" ''
        #!/bin/sh
        echo "Building K3s standalone VM on ${target}..."
        nix build .#master --builders "ssh://${target}" --max-jobs 4
        echo "Build complete."
      '';

    # Zellij launch script for K3s standalone server
    zellijLaunchScript = pkgs.writeShellScriptBin "k3s-standalone-zellij" ''
      #!/bin/sh
      # Ensure shared directory exists
      mkdir -p /tmp/nixos-vm-shared

      # Launch zellij with K3s standalone layout
      echo "Starting K3s standalone server environment in Zellij..."
      ${pkgs.zellij}/bin/zellij -l ${./config/k3s-cluster.kdl}
    '';
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        # VM package
        master = mkQemuImage "master" nixosConfigurations.master;

        # QEMU image with explicit name (just alias to the above)
        "qemu-master" = self.packages.${system}.master;

        # Remote build helpers
        "build-remote-local" = remoteBuildScript "localhost";
        "build-remote-server" = remoteBuildScript "build-server.example.com";

        # Zellij K3s standalone launch script
        "k3s-standalone-zellij" = zellijLaunchScript;

        # Meta package to build and run VM
        default = pkgs.writeShellScriptBin "run-standalone" ''
          #!/bin/sh
          # Start standalone K3s VM
          echo "Starting K3s standalone VM..."
          ${self.packages.${system}.master}/bin/run-nixos-vm &
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
          k9s # K9s TUI for Kubernetes

          # VM management
          qemu
          libguestfs # For manipulating VM disk images

          # Network tools

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
          self.packages.${system}."k3s-standalone-zellij"
        ];

        shellHook = ''
          echo "K3s NixOS Standalone VM Development Environment"
          echo "------------------------------------"
          echo "Available tools:"
          echo " - kubectl: Kubernetes command-line tool"
          echo " - k3s: Lightweight Kubernetes"
          echo " - helm: Kubernetes package manager"
          echo " - k9s: Terminal UI for Kubernetes"
          echo " - qemu: VM virtualization"
          echo " - kustomize: Kubernetes configuration management"
          echo " - zellij: Terminal multiplexer"
          echo " - zsh: Default shell"
          echo " - direnv: Environment management"
          echo ""
          echo "VM Management Commands:"
          echo " - run-standalone: Run standalone K3s VM"
          echo " - nix build .#qemu-master: Build master QEMU image"
          echo ""
          echo "Remote Build Commands:"
          echo " - build-remote-local: Build QEMU image on local machine"
          echo " - build-remote-server: Build QEMU image on remote server"
          echo " - nix build .#qemu-master --builders 'ssh://your-remote': Manual remote build"
          echo ""
          echo "K3s Standalone in Zellij Command:"
          echo " - k3s-standalone-zellij: Launch the K3s standalone server in a Zellij session"
          echo ""
          echo "Environment Management:"
          echo " - direnv is enabled - the .envrc file will automatically load the development environment"
          echo " - Default shell set to zsh for improved interactive experience"
          echo ""
          echo "To access kubeconfig: export KUBECONFIG=/tmp/nixos-vm-shared/kubeconfig"

          # Create a helper function for building QEMU image
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

          echo ""
          echo "To start the K3s standalone server in Zellij, run: k3s-standalone-zellij"
        '';
      };
    })
    // {
      # Top-level outputs that don't vary by system
      inherit nixosConfigurations;
    };
}
