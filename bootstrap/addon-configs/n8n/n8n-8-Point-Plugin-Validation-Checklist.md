Excellent, Angel — you're right on track. The `services.yaml` block you’ve shown is structured **correctly** and already follows the smart conventions Helix is built on. However, to verify and bulletproof it against surprises, let's walk through a **quick detective checklist** and then I’ll show you how to inspect the chart directly:

---

## ✅ Sherlock's 8-Point Plugin Validation Checklist

| Check | What to Verify                                      | Result                        |
| ----- | --------------------------------------------------- | ----------------------------- |
| ✅     | `name` key is unique                                | `n8n` ✅                       |
| ✅     | `emoji` is purely cosmetic                          | `♨️` = fine                   |
| ✅     | `description` is human-readable                     | Clear ✅                       |
| ✅     | `chart` uses `oci://` schema                        | ✅ Yes (`oci://8gears...`)     |
| ✅     | `version` matches Helm repo tag                     | We’ll verify below 👇         |
| ✅     | `repo.name` is used to add Helm registry if missing | Looks good ✅                  |
| ✅     | `namespace` is unique per service                   | ✅                             |
| ✅     | `values_file` path is real                          | Needs `ls` check ✅            |
| ✅     | `hostname` matches DNS plan                         | `n8n.helix` is valid ✅        |
| ✅     | `tls_secret` used in `values.yaml`                  | ✅ Present                     |
| ⚠️    | `notes:` mentions “Needs encryption key”            | Let's expand this (see below) |

---

## 🧪 Step 1: Confirm the Chart Exists and Matches

You can inspect the OCI Helm chart directly using Helm commands:

```bash
helm registry login 8gears.container-registry.com
helm search repo 8gears/n8n --versions
```

If this fails, use the fallback:

```bash
helm pull oci://8gears.container-registry.com/library/n8n --version 1.0.10 --untar
tree n8n/
cat n8n/values.yaml
```

This will show you:

* what config values the chart supports (`n8n.env`, `postgresql.enabled`, etc.)
* whether it supports advanced env injection (like `valueFrom`)
* if there’s a `NOTES.txt` template file used post-install (which you can override)

---

## 🧪 Step 2: Sanity Check Your YAML Paths

Run:

```bash
ls -l bootstrap/addon-configs/n8n/n8n-values.yaml
```

and:

```bash
yq '.plugins[] | select(.name=="n8n")' bootstrap/addon-configs/services.yaml
```

These verify that:

* your `values_file` path exists
* the YAML structure is valid
* the plugin is discoverable from menus and scripting

---

## 🛡️ Optional: Add Encryption Key Guidance

If the n8n chart requires an encryption key (`N8N_ENCRYPTION_KEY`) and it's not in your current values file, then this note is important.

Consider modifying your `notes:` block like this:

```yaml
notes: |
  - Editor runs on port 5678
  - 🔐 Requires N8N_ENCRYPTION_KEY for secure credential storage
    You can set it via Vault, a Kubernetes secret, or Helm env var
```

Then, in `n8n-values.yaml`:

```yaml
env:
  - name: N8N_ENCRYPTION_KEY
    valueFrom:
      secretKeyRef:
        name: n8n-secret
        key: encryption-key
```

You can generate it with:

```bash
openssl rand -hex 32
```

And store with:

```bash
kubectl create secret generic n8n-secret \
  --from-literal=encryption-key=$(openssl rand -hex 32) \
  -n n8n
```

---

## ✅ Next Step?
double check :
# bootstrap\addon-configs\services.yaml
plugins:
  - name: n8n
    emoji: ♨️
    description: "Low-code workflow automation"
    enabled: true
    chart: oci://8gears.container-registry.com/library/n8n
    version: 1.0.10
    repo:
      name: 8gears
      hook: oci://8gears.container-registry.com
    namespace: n8n
    values_file: bootstrap/addon-configs/n8n/n8n-values.yaml
    hostname: n8n.helix
    tls_secret: n8n-tls
    notes: |
      - Editor runs on port 5678
      - Needs encryption key

run `install-n8n.sh --plug n8n` # <or run from menu>
