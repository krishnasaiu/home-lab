# Homelab - Declarative K3s GitOps Stack

## 1. Overview
This project manages a self-hosted Kubernetes homelab running on **Debian Stable**. It is structured for GitOps-driven deployment using **K3s (Lightweight Kubernetes)**, allowing replication on any clean machine.

## 2. Directory Layout
The repository is organized as follows:
*   **`bootstrap/`**: Scripts to initialize the OS, install K3s, configure permissions, and setup base configurations.
*   **`kubernetes/system/`**: System infrastructure services (e.g. namespaces, ingress configurations, storage configs).
*   **`kubernetes/apps/`**: User-facing application workloads (e.g. Pi-hole DNS resolver).
*   **`scripts/`**: Automation tools and active sync scripts.

---

## 3. Replication & Setup Guide (Phase A & B)

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
Run the bootstrap script to install K3s and configure `kubectl` permissions for the `krishna` user:

```bash
# Clone the repository
git clone git@github.com:krishnasaiu/home-lab.git
cd home-lab

# Run bootstrap script
chmod +x bootstrap/install-k3s.sh
./bootstrap/install-k3s.sh
```

### Step 2: Establish Secure SSH Authentication with GitHub
To configure the git-sync daemon, generate a secure SSH key on the Debian host and link it to your GitHub account:
```bash
# Generate Ed25519 SSH Key
ssh-keygen -t ed25519 -C "krishna@homelab" -f ~/.ssh/id_ed25519 -N ""

# Start the ssh-agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Display the public key to copy to GitHub (Settings -> SSH and GPG Keys)
cat ~/.ssh/id_ed25519.pub
```

### Step 3: Deploy Applications
Deploy applications using K3s's native declarative Helm controller or standard manifests.

#### A. Pi-hole (DNS Resolver)
K3s has a built-in Helm Controller. Placing the `pihole-release.yaml` in the K3s auto-deploy directory will install/update Pi-hole automatically:
```bash
# Symlink to K3s auto-deploy directory for GitOps reconciliation
sudo ln -sf /home/krishna/home-lab/kubernetes/apps/pihole/pihole-release.yaml /var/lib/rancher/k3s/server/manifests/pihole-release.yaml
```

#### C. Retrieve Password
To fetch the auto-generated password for Pi-hole (or other apps in the future), use the provided helper script:
```bash
./scripts/get-password.sh pihole
```


---

## 4. Persistent Storage on Debian
To ensure application configuration persists when pods are rescheduled or rebuilt:
*   We use K3s' default `local-path` storage provisioner.
*   Storage is provisioned dynamically under `/var/lib/rancher/k3s/storage/` on the Debian host.
*   All persistent data is mapped to persistent volume claims (PVCs) defined in the Helm configuration (`pihole-values.yaml`), safeguarding against any data loss.

---

## 5. Automated Git Synchronization (Phase C)
The repository contains a sync daemon (`scripts/git-sync.sh`) that polls for remote updates from GitHub and auto-commits local edits made on the host (e.g. via Cockpit or manual edits).

### Running as a Systemd Service (Recommended)
To run the sync script as a persistent background daemon, create a systemd service file:

Create `/etc/systemd/system/homelab-git-sync.service`:
```ini
[Unit]
Description=Homelab Git-Sync Daemon
After=network.target

[Service]
Type=simple
User=krishna
WorkingDirectory=/home/krishna/home-lab
ExecStart=/home/krishna/home-lab/scripts/git-sync.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-git-sync.service
```

Check logs:
```bash
tail -f /var/log/homelab-git-sync.log
```

Alternatively, check full sync status (service status, git cleanliness, and remote diffs):
```bash
./scripts/check-sync-status.sh
```

---

## 6. Cluster Management using K9s (TUI)
K9s is a terminal-based user interface to interact with your Kubernetes cluster. It is completely open-source, fast, lightweight, and keyboard-driven.

### Installation
*   **On macOS (Local Machine)**:
    ```bash
    brew install k9s
    ```
*   **On Debian (Server Host)**:
    ```bash
    # Install via webinstall.dev
    curl -sS https://webinstall.dev/k9s | bash
    ```

### Usage

#### Setting up KUBECONFIG on your local Mac:
To connect to the cluster from your local Mac machine:
1. **Download the kubeconfig** from the Debian host using `scp`:
   ```bash
   mkdir -p ~/.kube
   scp krishna@<DEBIAN_SERVER_IP>:~/.kube/config ~/.kube/config-homelab
   ```
2. **Edit the server IP address** inside `~/.kube/config-homelab`. K3s sets the API address to `127.0.0.1` (localhost) by default. Replace `127.0.0.1` with your Debian host IP:
   ```yaml
   server: https://<DEBIAN_SERVER_IP>:6443
   ```
3. **Export the configuration** in your Mac's terminal:
   *   **Temporary** (current shell session):
       ```bash
       export KUBECONFIG=~/.kube/config-homelab
       ```
   *   **Permanent** (adds it to your zsh profile):
       ```bash
       echo 'export KUBECONFIG="$HOME/.kube/config-homelab"' >> ~/.zshrc
       source ~/.zshrc
       ```

Now launch the UI:
```bash
k9s
```

*   **Navigation**: Use arrow keys or `j`/`k` to navigate.
*   **Commands**: Press `:` to open command mode:
    *   `:pods` - View active Pods across namespaces.
    *   `:nodes` - View K3s node status.
    *   `:secrets` - View Kubernetes secrets.
    *   `:logs` - View log output for selected pods.
*   **Keys**: Press `?` to show the full list of keyboard shortcuts.

---

## 7. Continuous Delivery & Auto-Updates using Keel

We use **Keel** to automatically monitor container registries for new images (such as new versions of Pi-hole and Unbound) and roll out updates automatically with zero downtime.

### Deploying Keel
1. Keel is deployed declaratively using K3s's Helm controller. Create a symlink to auto-deploy Keel:
   ```bash
   sudo ln -sf /home/krishna/home-lab/kubernetes/system/keel/keel-release.yaml /var/lib/rancher/k3s/server/manifests/keel-release.yaml
   ```
2. K3s will automatically scan this directory and spin up the Keel operator in the `kube-system` namespace.

### How it works:
To enable auto-updates for any application (such as Pi-hole + Unbound), simply add Keel annotations to the resource's `metadata.annotations` or the Helm chart's `deploymentAnnotations`:
```yaml
deploymentAnnotations:
  keel.sh/policy: "force" # Force upgrade when the registry tag digest changes
  keel.sh/trigger: "poll"  # Monitor registry
  keel.sh/poll: "24h"      # Check once a day
```

---

## 8. FTP Server for Printer Scanners

We run a lightweight FTP server (`delfer/alpine-ftp-server`) in the cluster with `hostNetwork: true` to support printer scans directly to the Debian host filesystem.

### Deploying the FTP Server
1. Apply the deployment manifest:
   ```bash
   kubectl apply -f kubernetes/apps/ftp-server/ftp-deployment.yaml
   ```
2. Create the target directory on the Debian host if it does not exist, and set permissions:
   ```bash
   mkdir -p /home/krishna/scans
   chown -R krishna:krishna /home/krishna/scans
   ```

### Printer Configuration Settings
Configure your printer/scanner with the following parameters:
*   **Protocol**: FTP
*   **Host Address**: `192.168.50.120` (Debian Server IP)
*   **Port**: `21`
*   **Username**: `scanner`
*   **Password**: `password123` (Change this in `ftp-deployment.yaml` if needed)
*   **Directory/Path**: `/` or `/scans` (Files will be written to `/home/krishna/scans/` on the server)

---

## 9. Troubleshooting & Homelab Gotchas

Here are the manual steps and gotchas we encountered and solved during the setup:

### A. K3s Symlink Watcher Gotcha
*   **The Issue**: K3s watches for changes inside `/var/lib/rancher/k3s/server/manifests/`. However, the Go file-watcher does **not** detect modifications made to the target files of symlinks.
*   **The Fix**: Whenever you modify the Helm manifests locally in your git workspace, you must **touch** the symlink on the Debian host to update its modification time, forcing K3s to redeploy:
    ```bash
    sudo touch /var/lib/rancher/k3s/server/manifests/pihole-release.yaml
    ```

### B. Git-Sync Service Setup
*   **Git Identity**: Git requires an email and name to auto-generate commits. Set these on the Debian host:
    ```bash
    git config --global user.email "your-email@example.com"
    git config --global user.name "Your Name"
    ```
*   **Use SSH Remote URL**: The Debian clone must use an SSH remote URL, as HTTPS clones will prompt for credentials in the background and fail:
    ```bash
    cd ~/home-lab
    git remote set-url origin git@github.com:krishnasaiu/home-lab.git
    ```

### C. Unbound ConfigMap Order
*   Before K3s triggers the Pi-hole sidecar deployment, the ConfigMap containing `unbound.conf` must exist in the cluster so the container does not crash looking for the volume:
    ```bash
    kubectl apply -f kubernetes/apps/unbound/unbound-config.yaml
    ```

### D. Router DNS Configuration
*   **LAN DHCP DNS (Recommended)**: Point devices to your Pi-hole IP (`192.168.50.120`) via the router's **LAN -> DHCP Server -> DNS Server** settings (rather than WAN settings). This prevents router DNS caching and allows Pi-hole to report queries per individual client instead of listing everything under the router's IP.