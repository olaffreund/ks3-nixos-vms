# NixOS K3s Cluster with QEMU VMs

This project provides a Nix flake for setting up a three-node K3s cluster using QEMU virtual machines on NixOS. The cluster consists of one master node and two worker nodes, all integrated with Tailscale for secure networking.

## Features

- **Three NixOS VMs**: One master and two worker nodes
- **K3s Kubernetes**: Lightweight Kubernetes distribution
- **Tailscale Integration**: Secure networking between nodes
- **Shared Folder**: Easy file exchange between host and VMs
- **Sample Deployment**: PostgreSQL database and Nginx web interface

## Prerequisites

- NixOS with flakes enabled
- QEMU for virtualization
- Tailscale account (for authentication keys)

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
2. Replace `YOUR_TAILSCALE_AUTH_KEY` in the VM configuration files with your actual Tailscale auth key
3. Create the shared folder: `mkdir -p /tmp/nixos-vm-shared`
4. Start the cluster:
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

## Security Notes

- For production use, replace the hardcoded token with a secure value
- Don't commit Tailscale auth keys to version control
- Consider using Nix's secret management capabilities for sensitive data

## License

MIT