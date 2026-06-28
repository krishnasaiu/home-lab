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

### Step 1: Debian Machine Bootstrapping
Run the bootstrap script to install K3s (with default Traefik ingress disabled for custom reverse-proxy control) and configure `kubectl` permissions for user `krishna`:
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