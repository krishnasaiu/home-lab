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
*   **Network**: A static LAN IP assigned to the server (referenced as `<server_ip>` in the guide).

### B. Required Host Directories
Before applying manifests, create the local HostPath directories on the server to prevent volume mounting errors. Run the following on the host:
```bash
# Create scanner intake folder and Home Assistant config folders
mkdir -p /home/<username>/scans
mkdir -p /home/<username>/homeassistant_config

# Set ownership to prevent container permission conflicts
sudo chown -R <username>:<username> /home/<username>/scans /home/<username>/homeassistant_config
```

---

## 3. Step-by-Step Installation Guide

Follow these sequential phases to replicate the entire stack from scratch:

### Option A: Fully Automated Setup (Recommended Custom ISO)
1. **Fork this repository** to your own GitHub account.
2. Go to your repository's **Releases** tab and download the custom bootable installer ISO (`debian-12-amd64-CD-1.iso`) under the `latest` release tag.
3. Write this ISO to a USB flash drive (using Rufus, BalenaEtcher, or Ventoy).
4. Boot your clean server from the USB. **The installer runs with zero keystrokes**: it automatically partitions the disk, installs Debian Stable, creates the administrator user, pre-installs Cockpit (including the visual navigator), clones your repository fork, pre-configures your volume directories, sets up Home Assistant database mappings, and pre-installs the K3s server.
5. Once installation finishes, boot the server and proceed directly to **Phase 3: Bootstrap Flux CD**!

---

<details>
<summary><b>🔍 Manual Host Setup Reference (Click to expand)</b></summary>

If you choose not to use the automated ISO and want to configure the host system manually, follow these detailed preparation steps:

#### 1. Pre-create Required Host Directories
Create the scans and Home Assistant configuration folders:
```bash
# Create directories
mkdir -p /home/<username>/scans
mkdir -p /home/<username>/homeassistant_config

# Set ownership to prevent container permission conflicts
sudo chown -R <username>:<username> /home/<username>/scans /home/<username>/homeassistant_config
```

#### 2. Host Preparation (Cockpit & Hostname)
Configure your server hostname and install the admin cockpit:
```bash
# Update Hostname & Resolver mapping
sudo hostnamectl set-hostname homelab
sudo sed -i 's/127.0.1.1.*/127.0.1.1   homelab/g' /etc/hosts

# Install Cockpit & Core Utilities
sudo apt update
sudo apt install -y cockpit cockpit-podman wget

# Install 45Drives Visual File Manager Plugin (Cockpit Navigator)
wget https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.8/cockpit-navigator_0.5.8-1focal_all.deb
sudo apt install -y ./cockpit-navigator_0.5.8-1focal_all.deb
rm cockpit-navigator_0.5.8-1focal_all.deb

# Enable and start Cockpit Web Console (Port 9090)
sudo systemctl enable --now cockpit.socket
```

#### 3. Install Kubernetes (K3s Core)
Install K3s directly from the official upstream installer:
```bash
curl -sfL https://get.k3s.io | sh -
```

#### 4. Configure Home Assistant Database Link
Create or edit `/home/<username>/homeassistant_config/configuration.yaml` and append:
```yaml
# Configure Home Assistant core configuration
default_config:

# Database integration to redirect history to PostgreSQL
recorder:
  db_url: !env_var DB_URL
```

</details>

---

### Phase 3: Bootstrap Flux CD (GitOps)
1. Generate a **GitHub Classic Personal Access Token (PAT)** on GitHub with `repo` scope.
2. Export the token and run the Flux bootstrapper. The script will automatically fetch your active repository remote (supporting forks) and link the cluster to it:

```bash
export GITHUB_TOKEN="your_personal_access_token_here"
./bootstrap/bootstrap-flux-cd.sh
```

> [!NOTE]
> The bootstrapper generates PostgreSQL passwords, matches namespace secrets, rollouts dependencies, and links Flux. It takes roughly 2 minutes to complete syncing the apps.

### Phase 4: First-Time Application Setup

1.  **Configure Beszel credentials**: Beszel Hub is deployed, but requires you to register your admin account and save credentials.
    *   Create a secure secret in the cluster from your terminal to avoid committing plain text password to Git:
        ```bash
        kubectl create secret generic beszel-credentials -n default \
          --from-literal=username="your-admin-email@example.com" \
          --from-literal=password="your-beszel-admin-password"
        ```
    *   Open `http://<server_ip>:8090/`, log in, click **Add System**, set the name to `homelab`, and retrieve the **Agent Public Key** (`ssh-ed25519 ...`). 
    *   Update the `KEY` variable inside `kubernetes/apps/beszel/beszel-agent-deployment.yaml` with this public key to start system resource tracking.

2.  **Configure Uptime Kuma monitoring**: 
    *   Open `http://<server_ip>:3001/` and register your admin account.
    *   Add monitors for your local services. Since PostgreSQL and Redis do not run on the host network directly, monitor them using internal cluster DNS:
        *   **Postgres Host**: `postgres-service.default.svc.cluster.local` (Port `5432`)
        *   **Redis Host**: `redis-service.default.svc.cluster.local` (Port `6379`)
    *   Click **Status Pages** -> **Add New Status Page**, set the slug to `default`, check the boxes for all your monitors, and save. This enables the live summary status widget on your Homepage dashboard card.

3.  **Create Paperless Admin Account**: Run the Django administrator wizard:
   ```bash
   kubectl exec -it deployment/paperless -n default -c paperless -- createsuperuser
   ```

4.  **Fetch Auto-Generated Passwords**: Print database, dashboard, or FTP credentials using the utility script:
   ```bash
   # Fetch Pi-hole admin interface password
   ./scripts/get-password.sh pihole

   # Fetch PostgreSQL admin credentials
   ./scripts/get-password.sh postgres

   # Fetch Scanner FTP credentials
   ./scripts/get-password.sh ftp
   ```

---

## 4. Deployed Applications & Access Guide

Once synchronized, all apps are exposed via **Traefik Ingress** (Port 80) and bound locally via host network ports.

| Application | Local Port (Host IP) | Local DNS URL | Purpose |
| :--- | :--- | :--- | :--- |
| **Homepage** | `http://<server_ip>:3000/` | `http://dashboard.homelab/` | Unified Status Dashboard |
| **Pi-hole Admin** | `http://<server_ip>/admin/` | `http://pihole.homelab/admin/` | Ad-blocking & Local DNS Server |
| **Home Assistant**| `http://<server_ip>:8123/` | `http://homeassistant.homelab/` | Smart Home Hub |
| **Vaultwarden** | `http://<server_ip>:8080/` | `http://vaultwarden.homelab/` | Password Manager (Bitwarden) |
| **Paperless-ngx** | `http://<server_ip>:8000/` | `http://paperless.homelab/` | Document Archiver & OCR |
| **Uptime Kuma** | `http://<server_ip>:3001/` | `http://status.homelab/` | Service Availability Monitors |
| **pgweb Client** | `http://<server_ip>:8085/` | `http://pgweb.homelab/` | Web PostgreSQL Console |
| **Redis Commander**| `http://<server_ip>:8086/` | `http://redis-commander.homelab/` | Web Redis Console |
| **Beszel Hub** | `http://<server_ip>:8090/` | `http://beszel.homelab/` | Lightweight Server Resource Monitor |
| **Cockpit Console**| `https://<server_ip>:9090/` | N/A | Linux OS Dashboard |
| **Dozzle Logs**   | N/A                        | `http://logs.homelab/`            | Real-time Container Log Viewer      |

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
   scp <username>@<server_ip>:~/.kube/config ~/.kube/config-homelab
   ```
2. Replace `127.0.0.1` inside `~/.kube/config-homelab` with your server LAN IP `<server_ip>`.
3. Export the config path and load K9s:
   ```bash
   export KUBECONFIG=~/.kube/config-homelab
   k9s
   ```

### C. Trusting the Local Certificate Authority (Root CA) for HTTPS
To enable green trusted padlocks and secure connections on your devices:
1.  **Extract the Root CA certificate** from your cluster to your Mac:
    ```bash
    kubectl --kubeconfig=~/.kube/config-homelab get secret homelab-ca-secret -n cert-manager -o jsonpath="{.data['ca\.crt']}" | base64 --decode > root.crt
    ```
2.  **Trust it on your Mac**:
    Install the certificate into your system keychain as a trusted root:
    ```bash
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain root.crt
    ```
3.  **Trust it on iOS (iPhone/iPad)**:
    *   AirDrop `root.crt` from your Mac to your iOS device.
    *   Open the file on iOS, go to **Settings** → **VPN & Device Management** and install the **homelab-ca-root** profile.
    *   Go to **Settings** → **General** → **About** → **Certificate Trust Settings**, and toggle the switch to enable full trust for **`homelab-ca-root`**.

---

## 6. Scanner & FTP Automation

1.  **Scanner Uploads File**: Your physical network scanner uploads scans via FTP (using the parameter settings below).
2.  **Paperless Consumption**: Files land in `/home/<username>/scans` on the Debian server. The Paperless-ngx container watches this directory, reads and OCRs the PDF document, and **deletes the raw scanner file** once imported.

### Scanner Connection Settings
*   **Protocol**: FTP
*   **Host Address**: `<server_ip>`
*   **Port**: `21`
*   **Username**: `scanner`
*   **Password**: Automatically generated. Retrieve it by running `./scripts/get-password.sh ftp` on the host.
*   **Path**: `/`