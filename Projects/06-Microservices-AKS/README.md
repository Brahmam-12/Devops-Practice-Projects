# Project 06: Microservices on AKS — User Service + Product Service

## Architecture

```
          Internet
              │
  Azure Application Gateway / NGINX Ingress
  ┌───────────────────────────────────────────┐
  │  /users/*    →  user-service:3000         │
  │  /products/* →  product-service:3001      │
  └───────────────────────────────────────────┘
              │
     ┌────────┴────────┐
     │                 │
 user-service     product-service
 (ClusterIP)      (ClusterIP)
 2 replicas       2 replicas
     │                 │
     └────────┬────────┘
              │
          postgres
          (ClusterIP)
          PostgreSQL 15
```

**What each piece is:**

| Component | Type | Why |
|-----------|------|-----|
| NGINX Ingress | LoadBalancer (external IP) | Single entry point, routes by path |
| user-service | ClusterIP | Internal only — Ingress is the public face |
| product-service | ClusterIP | Same — not exposed directly to internet |
| postgres | ClusterIP | Database — internal only, never exposed |

**Why ClusterIP for services?**
ClusterIP means the service has an IP only reachable inside the cluster. The Ingress Controller is the only thing that gets a public IP. This is correct — your DB and app services should never be directly reachable from the internet.

---

## Folder Structure

```
06-Microservices-AKS/
├── user-service/
│   ├── src/index.js         ← Express app: GET/POST /users, GET /health
│   ├── package.json
│   └── Dockerfile
├── product-service/
│   ├── src/index.js         ← Express app: GET/POST /products, GET /health
│   ├── package.json
│   └── Dockerfile
├── postgres-init/
│   └── init.sql             ← Creates usersdb and productsdb on first run
├── docker-compose.yaml      ← Local testing: all 3 services + postgres
└── k8s/
    ├── namespace.yaml
    ├── postgres/
    │   ├── secret.yaml      ← DB credentials
    │   ├── deployment.yaml  ← PostgreSQL pod + PVC + init ConfigMap
    │   └── service.yaml     ← ClusterIP on port 5432
    ├── user-service/
    │   ├── deployment.yaml
    │   └── service.yaml
    ├── product-service/
    │   ├── deployment.yaml
    │   └── service.yaml
    └── ingress/
        └── ingress.yaml     ← Path-based routing /users → /products
```

---

## PART 1: Run Locally with Node.js (no Docker)

### Prerequisites
- Node.js 18+ installed: `node --version`
- PostgreSQL running locally on port 5432

### Step 1: Create the databases
```bash
# Connect to your local PostgreSQL
psql -U postgres

# Inside psql:
CREATE DATABASE usersdb;
CREATE DATABASE productsdb;
\q
```

### Step 2: Install dependencies and start user-service
```bash
cd user-service
npm install
DB_HOST=localhost DB_USER=postgres DB_PASSWORD=postgres123 npm start
```

You should see:
```
[user-service] users table ready
[user-service] listening on port 3000
```

### Step 3: Install dependencies and start product-service
Open a **new terminal**:
```bash
cd product-service
npm install
DB_HOST=localhost DB_USER=postgres DB_PASSWORD=postgres123 npm start
```

You should see:
```
[product-service] products table ready
[product-service] listening on port 3001
```

### Step 4: Test the APIs

**User Service (port 3000):**
```bash
# Health check
curl http://localhost:3000/health
# {"status":"ok","service":"user-service","timestamp":"..."}

# Create a user
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Veera", "email": "veera@company.com"}'
# {"id":1,"name":"Veera","email":"veera@company.com","created_at":"..."}

# Create another user
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Brahma", "email": "brahma@company.com"}'

# List all users
curl http://localhost:3000/users
# [{"id":1,"name":"Veera",...}, {"id":2,"name":"Brahma",...}]

# Get user by id
curl http://localhost:3000/users/1

# Delete a user
curl -X DELETE http://localhost:3000/users/1
```

**Product Service (port 3001):**
```bash
# Health check
curl http://localhost:3001/health

# Create products
curl -X POST http://localhost:3001/products \
  -H "Content-Type: application/json" \
  -d '{"name": "Laptop", "price": 999.99, "stock": 50}'

curl -X POST http://localhost:3001/products \
  -H "Content-Type: application/json" \
  -d '{"name": "Mouse", "price": 29.99, "stock": 200}'

# List all products
curl http://localhost:3001/products

# Get product by id
curl http://localhost:3001/products/1

# Update stock
curl -X PATCH http://localhost:3001/products/1/stock \
  -H "Content-Type: application/json" \
  -d '{"stock": 45}'
```

---

## PART 2: Run with Docker Compose (all services together)

### Prerequisites
- Docker Desktop installed and running

### Step 1: Build and start everything
```bash
# From the project root (where docker-compose.yaml is)
docker compose up --build

# First run output (in order):
# postgres    | database system is ready to accept connections
# postgres    | CREATE DATABASE (usersdb)
# postgres    | CREATE DATABASE (productsdb)
# user-service | [user-service] users table ready
# user-service | [user-service] listening on port 3000
# product-service | [product-service] products table ready
# product-service | [product-service] listening on port 3001
```

### Step 2: Test (same curl commands as above)
Both services are on the same ports — 3000 and 3001.

```bash
# Quick sanity check
curl http://localhost:3000/health
curl http://localhost:3001/health
```

### Step 3: Useful Docker Compose commands
```bash
# Run in background
docker compose up -d

# See logs
docker compose logs -f
docker compose logs -f user-service       # single service
docker compose logs -f product-service

# Stop everything
docker compose down

# Stop and delete the postgres data volume (fresh start)
docker compose down -v
```

### Step 4: Connect to Postgres directly (optional)
```bash
docker exec -it postgres psql -U postgres -d usersdb -c "SELECT * FROM users;"
docker exec -it postgres psql -U postgres -d productsdb -c "SELECT * FROM products;"
```

---

## PART 3: Deploy to Azure AKS

### Prerequisites
- Azure CLI installed and logged in: `az login`
- kubectl installed
- Docker Desktop running

---

### Step 1: Create Resource Group and ACR
```bash
RG="microservices-rg"
LOCATION="eastus"
ACR_NAME="microservicesacr$RANDOM"   # must be globally unique

az group create --name $RG --location $LOCATION

az acr create \
  --resource-group $RG \
  --name $ACR_NAME \
  --sku Basic

echo "Your ACR name: $ACR_NAME"
# Save this — you'll need it in Step 3 and in the k8s YAML files
```

---

### Step 2: Create AKS Cluster
```bash
CLUSTER_NAME="microservices-aks"

az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --node-count 2 \
  --node-vm-size Standard_B2s \
  --generate-ssh-keys \
  --attach-acr $ACR_NAME     # gives AKS permission to pull from your ACR

# Get kubectl credentials
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME

# Verify connection
kubectl get nodes
# NAME                               STATUS   ROLES   AGE   VERSION
# aks-nodepool1-xxx   Ready    agent   2m    v1.28.x
```

---

### Step 3: Build and Push Docker Images to ACR
```bash
# Login to ACR
az acr login --name $ACR_NAME

# Build and push user-service
docker build -t $ACR_NAME.azurecr.io/user-service:v1 ./user-service
docker push $ACR_NAME.azurecr.io/user-service:v1

# Build and push product-service
docker build -t $ACR_NAME.azurecr.io/product-service:v1 ./product-service
docker push $ACR_NAME.azurecr.io/product-service:v1

# Verify images are in ACR
az acr repository list --name $ACR_NAME
# ["product-service", "user-service"]
```

---

### Step 4: Update Image Names in Deployment YAMLs
Open these two files and replace `<YOUR_ACR_NAME>` with your actual ACR name:

- [k8s/user-service/deployment.yaml](k8s/user-service/deployment.yaml) — line with `image:`
- [k8s/product-service/deployment.yaml](k8s/product-service/deployment.yaml) — line with `image:`

```yaml
# Before:
image: <YOUR_ACR_NAME>.azurecr.io/user-service:v1

# After (example):
image: microservicesacr12345.azurecr.io/user-service:v1
```

---

### Step 5: Install NGINX Ingress Controller
```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
# This creates an Azure Load Balancer with a public IP automatically
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2

# Wait for external IP to be assigned (takes 2-3 minutes)
kubectl get svc -n ingress-nginx --watch
# NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP
# ingress-nginx-controller   LoadBalancer   10.0.123.45    20.x.x.x   ← wait for this
```

---

### Step 6: Deploy Everything to AKS
```bash
# 1. Create namespace
kubectl apply -f k8s/namespace.yaml

# 2. Deploy PostgreSQL (secret + configmap + deployment + pvc + service)
kubectl apply -f k8s/postgres/

# Wait for postgres to be ready
kubectl rollout status deployment/postgres -n microservices
kubectl get pods -n microservices

# 3. Deploy user-service
kubectl apply -f k8s/user-service/

# 4. Deploy product-service
kubectl apply -f k8s/product-service/

# 5. Apply Ingress
kubectl apply -f k8s/ingress/

# Verify everything is running
kubectl get all -n microservices
```

Expected output:
```
NAME                                  READY   STATUS    RESTARTS
pod/postgres-xxx                      1/1     Running   0
pod/user-service-xxx                  1/1     Running   0
pod/user-service-yyy                  1/1     Running   0
pod/product-service-xxx               1/1     Running   0
pod/product-service-yyy               1/1     Running   0

NAME                      TYPE        CLUSTER-IP     PORT(S)
service/postgres          ClusterIP   10.0.x.x       5432/TCP
service/user-service      ClusterIP   10.0.x.x       3000/TCP
service/product-service   ClusterIP   10.0.x.x       3001/TCP

NAME                               READY   UP-TO-DATE
deployment.apps/postgres           1/1     1
deployment.apps/user-service       2/2     2
deployment.apps/product-service    2/2     2
```

---

### Step 7: Get the Ingress External IP and Test

```bash
# Get the Ingress external IP
kubectl get ingress -n microservices
# NAME                    CLASS   HOSTS   ADDRESS        PORTS
# microservices-ingress   nginx   *       20.x.x.x       80

INGRESS_IP=$(kubectl get ingress microservices-ingress -n microservices \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Ingress IP: $INGRESS_IP"

# Test via Ingress (same API, now going through NGINX)
curl http://$INGRESS_IP/health               # 404 — no route for /health at root
curl http://$INGRESS_IP/users/health         # {"status":"ok","service":"user-service"}
curl http://$INGRESS_IP/products/health      # {"status":"ok","service":"product-service"}

# Create users through Ingress
curl -X POST http://$INGRESS_IP/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Veera", "email": "veera@company.com"}'

# Create products through Ingress
curl -X POST http://$INGRESS_IP/products \
  -H "Content-Type: application/json" \
  -d '{"name": "Laptop", "price": 999.99, "stock": 50}'

# List from Ingress
curl http://$INGRESS_IP/users
curl http://$INGRESS_IP/products
```

---

### Step 8: Verify Routing

```bash
# Confirm /users routes to user-service and NOT product-service
curl http://$INGRESS_IP/users/health
# service: "user-service"

curl http://$INGRESS_IP/products/health
# service: "product-service"

# Check Ingress events if routing doesn't work
kubectl describe ingress microservices-ingress -n microservices

# Check NGINX Ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | tail -20
```

---

## API Reference

### User Service

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/health` | — | `{status, service, timestamp}` |
| GET | `/users` | — | Array of users |
| POST | `/users` | `{name, email}` | Created user |
| GET | `/users/:id` | — | Single user |
| DELETE | `/users/:id` | — | Deleted user |

### Product Service

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/health` | — | `{status, service, timestamp}` |
| GET | `/products` | — | Array of products |
| POST | `/products` | `{name, price, stock}` | Created product |
| GET | `/products/:id` | — | Single product |
| PATCH | `/products/:id/stock` | `{stock}` | Updated product |
| DELETE | `/products/:id` | — | Deleted product |

---

## Cleanup (avoid Azure charges)

```bash
# Delete AKS resources only (keeps RG and ACR)
kubectl delete namespace microservices
kubectl delete namespace ingress-nginx

# Or delete everything
az group delete --name microservices-rg --yes --no-wait
```

---

## Troubleshooting

| Problem | Command | Fix |
|---------|---------|-----|
| Pod stuck Pending | `kubectl describe pod <name> -n microservices` | Check events (PVC, image pull) |
| ImagePullBackOff | `kubectl describe pod` → check image name | Fix ACR name in deployment YAML |
| postgres pod not ready | `kubectl logs postgres-xxx -n microservices` | Check secret values |
| Ingress 404 | `kubectl describe ingress -n microservices` | Check service name + port |
| Service no endpoints | `kubectl get endpoints -n microservices` | Check pod labels match service selector |
