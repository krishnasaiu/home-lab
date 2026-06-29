# Homelab - Declarative K3s GitOps Stack

A GitOps-managed Kubernetes homelab running on **Debian Stable**. Workloads are declaratively versioned and automatically synchronized using **Flux CD** on top of **K3s (Lightweight Kubernetes)**.

---

## 1. Directory Structure

*   **`bootstrap/`**: Scripts to initialize the OS, install K3s, configure namespaces, and bootstrap Flux CD.
*   **`kubernetes/apps/`**: Declarative Kubernetes manifests (deployments, services, ingresses, PVCs) for user workloads.
*   **`scripts/`**: Administration scripts (port forwarding tunnels, credential retrievals, health checks).

---

## 2. Prerequisites & Host Configuration

To replicate this homelab on a clean server, ensure your host satisfies the following:

### A. Hardware & OS
*   **OS**: Debian Stable (Minimal/Standard installation).
*   **Network**: A static LAN IP assigned to the server (we assume `192.168.50.120` in the configurations. If your IP is different, customize it inside `bootstrap/bootstrap-flux-cd.sh` or your local configurations).

### B. Required Host Directories
Before applying manifests, create the local HostPath directories on the server to prevent volume mounting errors. Run the following on the host:
```bash
# Create scanner intake folder and Home Assistant config folders
mkdir -p /home/krishna/scans
mkdir -p /home/krishna/homeassistant_config

# Set ownership to prevent container permission conflicts
sudo chown -R krishna:krishna /home/krishna/scans /home/krishna/homeassistant_config
```

---

## 3. Step-by-Step Installation Guide

Follow these sequential phases to replicate the entire stack from scratch:

### Phase 1: Host Preparation (Cockpit & Hostname)
Log in to your clean Debian server and configure the local hostname and administrative cockpit:

```bash
# 1. Update Hostname & Resolver mapping
sudo hostnamectl set-hostname homelab
sudo sed -i 's/127.0.1.1.*/127.0.1.1   homelab/g' /etc/hosts

# 2. Install Cockpit & Core Utilities
sudo apt update
sudo apt install -y cockpit cockpit-podman wget

# 3. Install 45Drives Visual File Manager Plugin (Cockpit Navigator)
wget https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.8/cockpit-navigator_0.5.8-1focal_all.deb
sudo apt install -y ./cockpit-navigator_0.5.8-1focal_all.deb
rm cockpit-navigator_0.5.8-1focal_all.deb

# 4. Enable and start Cockpit Web Console (Port 9090)
sudo systemctl enable --now cockpit.socket
```

### Phase 2: Install Kubernetes (K3s Core)
Clone your repository onto the server and execute the K3s bootstrapper:

```bash
# Clone your repository
git clone https://github.com/krishnasaiu/home-lab.git
cd home-lab

# Make the installer executable and run
chmod +x bootstrap/install-k3s.sh
./bootstrap/install-k3s.sh
```

### Phase 3: Bootstrap Flux CD (GitOps)
1. Generate a **GitHub Classic Personal Access Token (PAT)** on GitHub with `repo` scope.
2. Export the token and run the Flux bootstrapper. The script will automatically fetch your active repository remote (supporting forks) and link the cluster to it:

```bash
export GITHUB_TOKEN="your_personal_access_token_here"
./bootstrap/bootstrap-flux-cd.sh
```

> [!NOTE]
> The bootstrapper generates PostgreSQL passwords, matches namespace secrets, rollouts dependencies, and links Flux. It takes roughly 2 minutes to complete syncing the apps.

### Phase 4: Database Initializations
Once the core database pod is running:
1. **Initialize the Paperless Database**: The Postgres PVC was just initialized, meaning we must create the logical schema for Paperless-ngx manually:
   ```bash
   kubectl exec -it deployment/postgres -n default -c postgres -- psql -U postgres -c "CREATE DATABASE paperless;"
   ```
2. **Migrate Home Assistant to PostgreSQL**: 
   Append the following to the bottom of `/home/krishna/homeassistant_config/configuration.yaml`:
   ```yaml
   recorder:
     db_url: !env_var DB_URL
   ```
   Restart Home Assistant to apply:
   ```bash
   kubectl rollout restart deployment/homeassistant
   ```

### Phase 5: First-Time Application Setup
1. **Create Paperless Admin Account**: Run the Django administrator wizard:
   ```bash
   kubectl exec -it deployment/paperless -n default -c paperless -- createsuperuser
   ```
2. **Fetch Auto-Generated Passwords**: Print database or dashboard credentials:
   ```bash
   # Usage: ./scripts/get-password.sh [pihole | postgres]
   ./scripts/get-password.sh pihole
   ```

---

## 4. Deployed Applications & Access Guide

Once synchronized, all apps are exposed via **Traefik Ingress** (Port 80) and bound locally via host network ports.

| Application | Local Port (Host IP) | Local DNS URL | Purpose |
| :--- | :--- | :--- | :--- |
| **Homepage** | `http://192.168.50.120:3000/` | `http://dashboard.homelab/` | Unified Status Dashboard |
| **Pi-hole Admin** | `http://192.168.50.120/admin/` | `http://pihole.homelab/admin/` | Ad-blocking & Local DNS Server |
| **Home Assistant**| `http://192.168.50.120:8123/` | `http://homeassistant.homelab/` | Smart Home Hub |
| **Vaultwarden** | `http://192.168.50.120:8080/` | `http://vaultwarden.homelab/` | Password Manager (Bitwarden) |
| **Paperless-ngx** | `http://192.168.50.120:8000/` | `http://paperless.homelab/` | Document Archiver & OCR |
| **pgweb Client** | `http://192.168.50.120:8085/` | `http://pgweb.homelab/` | Web PostgreSQL Console |
| **Redis Commander**| `http://192.168.50.120:8086/` | `http://redis-commander.homelab/` | Web Redis Console |
| **Cockpit Console**| `https://192.168.50.120:9090/` | N/A | Linux OS Dashboard |

---

## 5. Administration & Remote Management

### A. Port Forwarding Tunnels (From your Mac)
To access database instances securely from local software (like DBeaver) or load Vaultwarden in a browser utilizing a Web Crypto secure context, execute the helper script:

```bash
# Forward only PostgreSQL (port 5432)
./scripts/port-forward.sh postgres

# Forward only Vaultwarden (port 8080)
./scripts/port-forward.sh vaultwarden

# Forward ALL forwarded services (Postgres, Vaultwarden, Paperless, Dashboard)
./scripts/port-forward.sh all
```

### B. Remote Cluster Management via K9s
To manage the cluster using K9s (TUI Interface) directly from your macOS terminal:
1. Copy the kubeconfig file to your Mac:
   ```bash
   mkdir -p ~/.kube
   scp krishna@192.168.50.120:~/.kube/config ~/.kube/config-homelab
   ```
2. Replace `127.0.0.1` inside `~/.kube/config-homelab` with the server LAN IP `192.168.50.120`.
3. Export the config path and load K9s:
   ```bash
   export KUBECONFIG=~/.kube/config-homelab
   k9s
   ```

---

## 6. Scanner & FTP Automation

1.  **Scanner Uploads File**: Your physical network scanner uploads scans via FTP (using the parameter settings below).
2.  **Paperless Consumption**: Files land in `/home/krishna/scans` on the Debian server. The Paperless-ngx container watches this directory, reads and OCRs the PDF document, and **deletes the raw scanner file** once imported.

### Scanner Connection Settings
*   **Protocol**: FTP
*   **Host Address**: `192.168.50.120`
*   **Port**: `21`
*   **Username**: `scanner`
*   **Password**: `password123` (Managed in `ftp-deployment.yaml`)
*   **Path**: `/`