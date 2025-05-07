# NixOS K3s Cluster with QEMU VMs

This project provides a Nix flake for setting up a three-node K3s cluster using QEMU virtual machines on NixOS. The cluster consists of one master node and two worker nodes.

## Features

- **Three NixOS VMs**: One master and two worker nodes
- **K3s Kubernetes**: Lightweight Kubernetes distribution
- **Shared Folder**: Easy file exchange between host and VMs
- **Sample Deployment**: PostgreSQL database and Nginx web interface
- **QEMU Disk Images**: Build standalone QEMU disk images for deployment
- **Remote Building**: Support for remote building of VM images

## Prerequisites

- NixOS with flakes enabled
- QEMU for virtualization

## Directory Structure

```
ks3-nixos-vms/
├── flake.nix                 # Main flake configuration
├── cluster/                  # VM configurations
│   ├── default.nix           # Common configuration
│   ├── master.nix            # K3s master node
│   ├── worker1.nix           # K3s worker node 1
│   └── worker2.nix           # K3s worker node 2
└── deployment/               # Kubernetes deployments
    ├── database.yaml         # Database deployment
    └── nginx.yaml            # Nginx deployment that connects to the DB
```

## Setup Instructions

1. Clone this repository
2. Create the shared folder: `mkdir -p /tmp/nixos-vm-shared`
3. Start the cluster:
   ```
   nix run
   ```

### Accessing the Cluster

Once the VMs are running:

1. The kubeconfig file will be copied to `/tmp/nixos-vm-shared/kubeconfig`
2. Access the master node and verify the cluster:
   ```
   k3s kubectl get nodes
   ```
3. Access the web interface by navigating to the master node's IP address in a browser

## Development Environment

Enter the development environment with:

```bash
nix develop
```

This provides access to all necessary tools including kubectl, k3s, helm, qemu, and more.

## Building QEMU Images

### Local Builds

Build individual node QEMU disk images:

```bash
# Build master node image
nix build .#qemu-master

# Build worker node images
nix build .#qemu-worker1
nix build .#qemu-worker2
```

### Building All Images at Once

You can build all VM images in a single command:

```bash
nix build .#qemu-images-all
```

The resulting VM images will be available in the `./result/` directory.

### Remote Builds

Build the images on a remote machine:

```bash
# Using the preconfigured remote builder
build-remote

# Manual remote build to any machine
nix build .#qemu-images-all --builders 'ssh://your-remote-machine'
```

### Helper Functions

When in the development shell, you can use helper functions:

```bash
# Build specific node images
build_qemu_image master
build_qemu_image worker1
build_qemu_image worker2
```

## Running the Cluster

### Starting All VMs at Once

The simplest way to start all VMs in the correct order is:

```bash
nix run
```

This runs the preconfigured `run-cluster` script which:
1. Starts the master node first
2. Waits 10 seconds for the master to initialize
3. Starts both worker nodes simultaneously
4. Keeps the terminal active until all VM processes exit

Alternatively, you can build the script once and use it directly:

```bash
# Build the script
nix build .#default

# Run the resulting script
./result/bin/run-cluster
```

## Testing the Database Connection

The sample application deploys:

1. A PostgreSQL database
2. A Node.js application that checks connectivity to the database
3. An Nginx web server that provides a simple UI to test the database connection

Access the web UI by navigating to the master node's IP address in your browser. Click the "Check Database Connection" button to test connectivity.

## Customization

- Modify VM resources in `cluster/default.nix`
- Change K3s configuration in the master and worker node files
- Add more Kubernetes deployments to the `deployment` directory
- Configure your own remote build targets in the `remoteBuild` section of the flake.nix file

## Security Notes

- For production use, replace the hardcoded token with a secure value
- Consider using Nix's secret management capabilities for sensitive data

## License

MIT