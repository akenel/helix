# 🚀 HELIX Quick Start Guide

> Set up a TLS-secure, production-grade Kubernetes platform with one command.

---

## 🛠 Prerequisites

Before you run Helix, make sure the following tools are installed:

```bash
brew install mkcert helm yq jq k3d
mkcert -install
````

Also confirm:

* Docker is running
* Firefox has launched once (for mkcert CA trust)
* You’ve done `helm repo update`

---

## 📦 Installation

Clone the Helix platform repo:

```bash
git clone https://github.com/akenel/helix.git
cd helix
./run.sh
```

Helix will guide you through:

* TLS setup (mkcert + cert-manager)
* Vault & Keycloak deployment
* Optional add-ons (n8n, MinIO, Istio, etc.)
* Live diagnostics (location, weather, system info)

---

## 🧪 Sanity Check

Once complete, you should see:

* `vault.helix` and `keycloak.helix` open over HTTPS
* TLS certificates with mkcert CA in your browser
* Traefik routing to services
* ClusterIssuer and cert-manager-csi ready

---

## ⚡️ Developer Workflow

To reset and rebuild:

```bash
./bootstrap/99-reset.sh
./run.sh
```

Or run individual steps:

```bash
./bootstrap/01_create-cluster.sh
./bootstrap/02_cert-bootstrap.sh
./bootstrap/04-deploy-identity-stack.sh
```

---

## 🧠 Troubleshooting

| Problem                                   | Fix                               |
| ----------------------------------------- | --------------------------------- |
| "certificate signed by unknown authority" | Run `mkcert -install` again       |
| Vault doesn’t start                       | Check `vault.env` secrets or logs |
| Firefox not trusting cert                 | Start Firefox once, then retry    |
| CSI pod cert not mounted                  | Verify CSI DaemonSet is running   |

---

## 🧬 Next Steps

* Install add-ons
* Customize themes, realms, TLS configs
* Wire into CI/CD
* Add your own plugins via `addons/`

🎉 Welcome to Helix.

````

Save this as: `docs/HELIX_QUICK_START.md`

---

### 3. `addons/README.md` — Contributor Guide ✅ *Now Available*

```markdown
# 🧩 Add-Ons in Helix

Helix supports dynamic, runtime-discoverable add-ons.

Add-ons are located in `bootstrap/addons/` and follow this simple convention:

## 🧬 Plugin Structure

Each plugin is a script named `install-<name>.sh`, for example:

````

install-n8n.sh
install-istio.sh
install-minio.sh

````

## 📜 Plugin Contract

Each script must define at least:

```bash
PLUGIN_NAME="n8n"
PLUGIN_DESC="Workflow automation for DevOps"

run_plugin() {
  echo "Installing $PLUGIN_NAME..."
  # Do something real here
}
````

Helix automatically scans the `addons/` directory for `install-*.sh` and adds them to the interactive menu.

## 🧪 Example

```bash
# install-portainer.sh
PLUGIN_NAME="Portainer"
PLUGIN_DESC="Web-based Docker & K8s dashboard"

run_plugin() {
  helm install portainer portainer/portainer \
    --namespace portainer --create-namespace \
    -f ../configs/portainer/portainer-values.yaml
}
```

Make it executable:

```bash
chmod +x install-portainer.sh
```

---

## 🤝 Submitting Add-ons

We welcome contributions!

* Fork the repo
* Add your plugin to `bootstrap/addons/`
* Ensure it follows the contract
* Test it
* Open a Pull Request 🎉

````

Save this as: `bootstrap/addons/README.md`

---

### 4. ✅ Chuck Norris GIF Injection Plan (Add Later)

At the bottom of the README, right before the final words:

```markdown
## 🥋 Chuck Norris Approved

Because no system is secure until Chuck says so.

![Chuck Norris](https://media.giphy.com/media/8vQSQ3cNXuDGo/giphy.gif)
````

> 💡 **Pro Tip:** Host the GIF locally in `assets/` if you're concerned about external dependency reliability later.

---

## ✅ PHASE 3: BRANCH & PUSH PLAN

Once these are done:

1. Commit all essentials:

```bash
git add .
git commit -m "Initial Helix platform structure, docs, and bootstrap system"
```

2. Push the `main` branch:

```bash
git remote add origin https://github.com/akenel/helix.git
git branch -M main
git push -u origin main
```

3. Start a new branch for the plugin work:

```bash
git checkout -b feature/plugin-discovery
```

---
