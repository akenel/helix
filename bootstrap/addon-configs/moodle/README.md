# Moodle on Kubernetes with Helm

This guide describes how to deploy Moodle on a Kubernetes cluster using the Bitnami Helm chart and access it locally via port-forwarding. Tested with chart version `27.0.3`.
https://artifacthub.io/packages/helm/bitnami/moodle
---

## 🚀 Deployment Instructions

### 1. Add the Bitnami Helm Repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install my-moodle bitnami/moodle --version 27.0.3

Capital! The case of the Vanishing Admin is now closed. Let us now, with the precision of a well-folded cravat and the clarity of a Watson journal, document this Moodle deployment in a `README.md`—so others may follow your footsteps without falling into the same deductive labyrinth.

---

## 📝 `README.md` — Deploying Moodle with Helm (Bitnami Chart)

````markdown
# Moodle on Kubernetes with Helm

This guide describes how to deploy Moodle on a Kubernetes cluster using the Bitnami Helm chart and access it locally via port-forwarding. Tested with chart version `27.0.3`.

---

## 🚀 Deployment Instructions

### 1. Add the Bitnami Helm Repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
````

### 2. Install Moodle (version 27.0.3)

```bash
helm install my-moodle bitnami/moodle --version 27.0.3 -n moodle --create-namespace
```

> Note: You may override default values using `--set` or a custom `values.yaml` file.

---

## 🔐 Access Credentials

After installation, Moodle will generate a password and store it in a Kubernetes Secret.

### 1. Get the Moodle Admin Password

```bash
kubectl get secret my-moodle -n moodle -o jsonpath="{.data.moodle-password}" | base64 --decode && echo
```

### 2. Moodle Username

By default, the username is:

```
user
```

> Note: The chart **does not** create an `admin` user by default.

---

## 🌐 Accessing Moodle Locally

### 1. Port Forward to the Moodle Service

```bash
kubectl port-forward svc/my-moodle 8080:80 -n moodle
```

### 2. Open Moodle in Your Browser

```
http://127.0.0.1:8080
```

---

## 🔧 Resetting the Admin Password (Optional)

If you need to reset the Moodle password from inside the pod:

### 1. Get the Pod Name

```bash
kubectl get pods -n moodle
```

### 2. Access the Pod

```bash
kubectl exec -n moodle -it <moodle-pod-name> -- bash
```

### 3. Run the Password Reset Script

```bash
php /bitnami/moodle/admin/cli/reset_password.php
```

Enter the **username** (likely `user`) and the new password when prompted.

---

## ✅ Confirm Login

Visit:

```
http://127.0.0.1:8080/login
```

Enter:

* **Username**: `user`
* **Password**: *(as retrieved or reset)*

You should now be logged in as the site administrator.

---

## 🧽 Optional: Clean Up

```bash
helm uninstall my-moodle -n moodle
kubectl delete namespace moodle
```

---

## 🧠 References

* [Bitnami Moodle Helm Chart](https://artifacthub.io/packages/helm/bitnami/moodle)
* [Moodle Docs](https://docs.moodle.org/)

```
USER ADMIN Notes:

Most certainly! Let me walk you through what each command did and **why** it worked, in the order of operations you followed to **reset the Moodle admin password** via the CLI within your Kubernetes environment.

---

## 🧠 What You Actually Did to Reset the Moodle Password (Explained Step-by-Step)

---

### 🔍 Step 1: List the Secrets in the Namespace

```bash
kubectl get secrets -n moodle
```

**What it does**:
This lists all Kubernetes **Secrets** in the `moodle` namespace. A Helm chart often stores sensitive credentials (like admin passwords) in Secrets automatically created during deployment.

You found a secret named `moodle`—that was the one containing your admin password.

---

### 🗝️ Step 2: View the Moodle Secret

```bash
kubectl get secret moodle -n moodle -o yaml
```

**What it does**:
This displays the full YAML definition of the secret named `moodle`. Inside the `.data` field, you saw:

```yaml
data:
  moodle-password: aTlLWkp4NlJYVQ==
```

The value was **base64 encoded**, which is standard practice for Kubernetes Secrets.

---

### 🔐 Step 3: Decode the Password

```bash
echo aTlLWkp4NlJYVQ== | base64 --decode
```

**What it does**:
This decodes the base64-encoded string into plain text. In your case, the password came out as:

```
i9KZJx6RXU
```

At this point, you had the Moodle **admin password**, but still needed to confirm the **username**—which turned out to be `user` (not `admin`, as some might assume).

---

### 🧑‍💻 Step 4: Enter the Moodle Pod

```bash
kubectl exec -n moodle -it <moodle-pod-name> -- bash
```

**What it does**:
This command starts an **interactive shell** inside the running Moodle pod, allowing you to execute commands as if you were inside the Linux container where Moodle is running.

You used this to run Moodle's internal CLI tool.

---

### 🔧 Step 5: Run Moodle's Password Reset Script

```bash
php /bitnami/moodle/admin/cli/reset_password.php
```

**What it does**:
This is a Moodle-provided PHP script located in the Moodle installation directory. It allows you to **manually reset the password of any user**—including the administrator.

When you ran it, it prompted:

```
Enter username (manual authentication only):
```

You typed `user`.

Then it asked for a **new password**, which you typed securely.

**Result**: The system updated the password for the `user` account directly in the Moodle database—**without needing to log in through the web interface**.

---

## 🎯 Final Outcome

You used the combination of:

* **Kubernetes secrets** (to get the original password),
* **Pod shell access** (to get inside the container),
* and **Moodle CLI tools** (to reset the password)

To fully regain control of your Moodle admin account.

---

Would you like this technical explanation added to your `README.md` as a special section for advanced users or maintainers?
