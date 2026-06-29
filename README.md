# Homelab - Declarative K3s GitOps Stack

## 1. Overview
This project manages a self-hosted Kubernetes homelab running on **Debian Stable**. It is structured for automated **GitOps-driven deployment using Flux CD** on top of **K3s (Lightweight Kubernetes)**, allowing easy replication on any clean machine.

## 2. Directory Layout
The repository is organized as follows:
*   **`bootstrap/`**: Scripts to initialize the OS, install K3s, configure permissions, and bootstrap Flux CD.
*   **`kubernetes/flux-system/`**: Flux CD core system synchronization manifests (automatically managed).
*   **`kubernetes/apps/`**: Declarative user workloads (e.g. Pi-hole, Home Assistant, FTP server) managed via Flux.
*   **`scripts/`**: Homelab utility scripts (e.g. password retrieval and health checks).

---

## 3. Replication & Setup Guide

### Step 0: Host OS Initialization (Hostname & Cockpit)
Before installing Kubernetes, initialize the server hostname and install the Cockpit management console along with the 45Drives visual file manager plugin:

```bash
# 1. Update Hostname & Local Networking Resolver
sudo hostnamectl set-hostname homelab
sudo sed -i 's/127.0.1.1.*/127.0.1.1   homelab/g' /etc/hosts

# 2. Install Cockpit & Core Utilities
sudo apt update
sudo apt install -y cockpit cockpit-podman wget

# 3. Add 45Drives Visual File Manager Plugin (Cockpit Navigator)
wget https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.8/cockpit-navigator_0.5.8-1focal_all.deb
sudo apt install -y ./cockpit-navigator_0.5.8-1focal_all.deb
rm cockpit-navigator_0.5.8-1focal_all.deb

# 4. Enable and start the Cockpit web service (Port 9090)
sudo systemctl enable --now cockpit.socket
```

### Step 1: Debian Machine Bootstrapping
Clone the repository and run the bootstrap script to install K3s and configure local `kubectl` user permissions:

```bash
# Clone the repository
git clone https://github.com/krishnasaiu/home-lab.git
cd home-lab

# Run bootstrap script
chmod +x bootstrap/install-k3s.sh
./bootstrap/install-k3s.sh
```

### Step 2: Bootstrap Flux CD (GitOps)
Generate a GitHub Classic Personal Access Token (PAT) with `repo` scope, then run our automated Flux bootstrapper. This script will install the Flux CLI, pre-populate cluster environment variables, disable deprecated host services, and link your repository:

```bash
# Run the Flux bootstrapper
./bootstrap/bootstrap-flux-cd.sh
```

Flux CD will configure a secure, read-only deploy key on GitHub and begin synchronizing all applications from your repository automatically.

---

## 4. Managing Applications

Because we use GitOps, **there are no deploy scripts to run on the server**. Your git repository is the single source of truth.

### How to update or deploy an application:
1. Make your changes in the `kubernetes/apps/` manifests on your local Mac.
2. Commit and push the changes:
   ```bash
   git add .
   git commit -m "feat: customize Pi-hole DNS entries"
   git push origin main
   ```
3. Within 60 seconds, Flux will detect the push, reconcile the change, and apply it directly to the cluster.

### Retreiving Passwords
To fetch the auto-generated credentials for your apps, run the helper script on the Debian server:
```bash
./scripts/get-password.sh pihole
```

---

## 5. Persistent Storage
To ensure application configuration persists when pods are rescheduled or rebuilt:
*   We use K3s' default `local-path` storage provisioner.
*   Storage is provisioned dynamically under `/var/lib/rancher/k3s/storage/` on the Debian host.
*   Persistent Volume Claims (PVCs) are declared directly in your app manifests to ensure zero data loss.

---

## 6. Cluster Management using K9s (TUI)
K9s is a terminal-based user interface to interact with your Kubernetes cluster.

### Installation
*   **On macOS (Local Machine)**:
    ```bash
    brew install k9s
    ```
*   **On Debian (Server Host)**:
    ```bash
    curl -sS https://webinstall.dev/k9s | bash
    ```

### Connecting from your local Mac:
1. **Download the kubeconfig** from the Debian host:
   ```bash
   mkdir -p ~/.kube
   scp krishna@192.168.50.120:~/.kube/config ~/.kube/config-homelab
   ```
2. **Edit the server IP address** inside `~/.kube/config-homelab`. Replace `127.0.0.1` with your Debian host IP:
   ```yaml
   server: https://192.168.50.120:6443
   ```
3. **Export the configuration** in your Mac's terminal:
   ```bash
   export KUBECONFIG=~/.kube/config-homelab
   ```

Now launch the UI:
```bash
k9s
```

---

## 7. FTP Server for Printer Scanners
We run a lightweight FTP server (`delfer/alpine-ftp-server`) in the cluster with `hostNetwork: true` to support printer scans directly to the Debian host filesystem.

### Printer Configuration Settings
Configure your printer/scanner with the following parameters:
*   **Protocol**: FTP
*   **Host Address**: `192.168.50.120` (Debian Server IP)
*   **Port**: `21`
*   **Username**: `scanner`
*   **Password**: `password123` (Managed in `ftp-deployment.yaml`)
*   **Directory/Path**: `/` (Files will be written to `/home/krishna/scans/` on the server)

---

## 8. Homelab Gotchas & DNS Configurations

### A. Router DNS Configuration
*   **LAN DHCP DNS (Recommended)**: Point devices to your Pi-hole IP (`192.168.50.120`) via the router's **LAN -> DHCP Server -> DNS Server** settings (rather than WAN settings). This prevents router DNS caching and allows Pi-hole to report queries per individual client instead of listing everything under the router's IP.

### B. Traefik Ingress Host Constraints
*   Standard Ingress specs reject raw IP addresses as routing hosts. To support accessing dashboards via both IP (`http://192.168.50.120/`) and domain (`http://pihole.homelab/`), use a separate custom Ingress containing a catch-all rule (omitting the `host` field).