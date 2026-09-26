# Full DevOps Pipeline — How Every File Connects

## The Complete Flow

```
Developer writes code
        │
        │  git push
        ▼
   GitHub Repository
        │
        │  webhook (HTTP POST to Jenkins URL)
        ▼
   Jenkins (Jenkinsfile runs)
        │
        ├─ 1. Checkout code
        ├─ 2. npm install + tests
        ├─ 3. docker build → image with new code
        ├─ 4. trivy scan → check for CVEs
        ├─ 5. docker push → image goes to ACR
        ├─ 6. sed update → deployment.yaml image tag updated
        └─ 7. git push → updated manifest pushed to GitHub
                │
                │  ArgoCD polls every 3 minutes (or via webhook)
                ▼
          ArgoCD detects deployment.yaml changed
                │
                │  kubectl apply -f k8s/user-service/deployment.yaml
                ▼
          Kubernetes API Server
                │
                ├─ Deployment Controller creates new ReplicaSet
                ├─ ReplicaSet creates new Pods
                ├─ Scheduler places Pods on nodes
                ├─ Kubelet pulls new image from ACR
                ├─ New Pods start → readinessProbe passes
                ├─ Service updates EndpointSlice (adds new pods, removes old)
                └─ Old Pods terminate gracefully
                        │
                        ▼
              Users served by new version ✅
```

---

## How Every File You Created Fits Into This Flow

### Local Development Phase

```
docker-compose.yaml
```
- Used by developers BEFORE pushing to Git
- Runs all 3 services (postgres + user-service + product-service) locally
- Tests the code and Docker containers work together
- Command: `docker compose up --build`
- Does NOT go to AKS — local only

---

### CI Phase (Jenkins runs these)

```
user-service/Dockerfile
product-service/Dockerfile
```
- Jenkins stage **Docker Build** reads this file
- `docker build -t acr.io/user-service:42 ./user-service`
- Defines HOW to package the Node.js app into a container image
- Node.js + dependencies + source code → one portable image

```
Jenkinsfile
```
- Jenkins reads this automatically when triggered
- Defines all 7 CI stages (checkout → test → build → scan → push → update → commit)
- Lives in the app repo root
- One Jenkinsfile per service (or parameterized for multiple services)

---

### CD Phase (ArgoCD applies these to AKS)

```
k8s/namespace.yaml
```
- Creates the `microservices` namespace in AKS
- Applied ONCE manually or via ArgoCD infrastructure app
- `kubectl apply -f k8s/namespace.yaml`
- All other resources go inside this namespace

```
k8s/postgres/secret.yaml
```
- Stores DB credentials (username + password)
- Applied by ArgoCD before services start
- user-service and product-service read DB_USER and DB_PASSWORD from this Secret
- Never hardcoded in deployment.yaml

```
k8s/postgres/deployment.yaml
```
- Tells Kubernetes: run 1 PostgreSQL pod
- Includes PVC (disk for data) + ConfigMap (init.sql to create databases)
- Applied by ArgoCD (infrastructure app)
- Postgres pod starts BEFORE service pods (they depend on DB)

```
k8s/postgres/service.yaml
```
- Gives postgres a stable DNS name: `postgres` inside the cluster
- user-service sets DB_HOST=postgres → resolves to this Service's ClusterIP
- Type ClusterIP = internal only, never exposed to internet

```
k8s/user-service/deployment.yaml       ← THIS is what Jenkins updates
k8s/product-service/deployment.yaml    ← THIS is what Jenkins updates
```
- **This is the key file in GitOps**
- Jenkins changes: `image: acr.io/user-service:41` → `image: acr.io/user-service:42`
- ArgoCD detects this change → applies to AKS → rolling update happens
- Contains: replicas, image, env vars (from Secret), readinessProbe, livenessProbe, resources

```
k8s/user-service/service.yaml
k8s/product-service/service.yaml
```
- ClusterIP Services — give pods a stable internal address
- Created ONCE, rarely change
- Ingress routes to these Services
- Services route to pods via label selector

```
k8s/ingress/ingress.yaml
```
- The single entry point for all external HTTP traffic
- Routes /users → user-service, /products → product-service
- Created ONCE, rarely change (unless you add new routes)

```
argocd/user-service-app.yaml
```
- Tells ArgoCD: watch this Git path, deploy to this namespace
- Applied ONCE: `kubectl apply -f argocd/user-service-app.yaml`
- After that: ArgoCD automatically syncs every time deployment.yaml changes in Git

---

## Setup Order (Do This Once)

### Step 1: Create AKS + ACR (Infrastructure)
```bash
az group create --name microservices-rg --location eastus
az acr create --name microservicesacr --resource-group microservices-rg --sku Basic
az aks create --name microservices-aks --resource-group microservices-rg \
  --node-count 2 --attach-acr microservicesacr --generate-ssh-keys
az aks get-credentials --name microservices-aks --resource-group microservices-rg
```

### Step 2: Deploy Infrastructure to AKS
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres/
kubectl apply -f k8s/ingress/
```

### Step 3: Install NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

### Step 4: Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Step 5: Register Applications in ArgoCD
```bash
kubectl apply -f argocd/user-service-app.yaml
# ArgoCD detects k8s/user-service/ folder and deploys to AKS
```

### Step 6: Setup Jenkins
```bash
# In Jenkins:
# 1. Install plugins: Git, Pipeline, Docker, Credentials
# 2. Add credentials:
#    - GitHub token  (ID: github-credentials)
#    - ACR password  (ID: acr-credentials)
# 3. Create Pipeline job → select "Pipeline from SCM" → point to your repo
# 4. GitHub repo → Settings → Webhooks → add Jenkins URL/github-webhook/
```

### Step 7: First Manual Deploy (before pipeline is set up)
```bash
# Build and push images manually once
docker build -t microservicesacr.azurecr.io/user-service:1 ./user-service
docker build -t microservicesacr.azurecr.io/product-service:1 ./product-service
az acr login --name microservicesacr
docker push microservicesacr.azurecr.io/user-service:1
docker push microservicesacr.azurecr.io/product-service:1

# Update deployment.yaml files with image tag :1
# Then git push → ArgoCD deploys
```

---

## After Setup: Everyday Developer Flow

```bash
# Developer changes a file in user-service/src/index.js
# Then:
git add .
git commit -m "fix: add pagination to GET /users"
git push origin main

# What happens automatically (no manual steps):
# 1. GitHub webhook fires → Jenkins starts
# 2. Jenkins: test → build → scan → push image :43 to ACR
# 3. Jenkins: updates deployment.yaml to image: acr.io/user-service:43
# 4. Jenkins: git push the updated deployment.yaml
# 5. ArgoCD detects change → kubectl apply
# 6. AKS: rolling update → new pods with :43 start, old pods stop
# 7. Users now get the new version (in ~5 minutes total)
```

---

## Rollback

If version :43 has a bug:
```bash
# Option 1: Git revert (preferred — GitOps way)
git revert HEAD
git push origin main
# ArgoCD detects revert → rolls back to :42 automatically

# Option 2: kubectl rollout (emergency, bypasses GitOps)
kubectl rollout undo deployment/user-service -n microservices
# Then update Git to match what's running (sync Git with cluster)

# Option 3: ArgoCD UI
# ArgoCD UI → user-service app → History → select previous version → Rollback
```

---

## What Each Tool Does

| Tool | Role | When it runs |
|------|------|-------------|
| **Docker Compose** | Local dev environment | Developer runs locally |
| **GitHub** | Source of truth for code AND manifests | Always |
| **Jenkins** | CI — builds, tests, scans, pushes image | On every git push |
| **ACR** | Stores Docker images | After Jenkins pushes |
| **ArgoCD** | CD — watches Git, deploys to K8s | Continuously (every 3 min poll) |
| **AKS** | Runs the containers | Always |
| **NGINX Ingress** | Routes external HTTP to services | Always |
| **Prometheus + Grafana** | Monitors pods, nodes, services | Always |
