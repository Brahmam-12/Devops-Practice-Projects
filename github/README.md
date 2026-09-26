# Company Microservices — Repository Architecture

## Why 4 Repositories, Not 1?

```
Single repo (course project):        Multi-repo (real company):
──────────────────────────────────   ────────────────────────────────────────
Everything in one place.             Each concern is isolated.

If infra code is broken →            If infra code is broken →
  all service pipelines fail.          only infra pipeline fails.
                                       Services still deploy normally.

Any developer can accidentally        App developers cannot touch Terraform.
  delete a Terraform resource.         DevOps team owns infrastructure repo.

ArgoCD watches your whole repo →      ArgoCD watches ONLY gitops-repo →
  every code commit triggers it.        only manifest changes trigger deploys.
```

---

## The 4 Repositories

```
github.com/company/
│
├── user-service               ← Team: backend developers
│   │                            Access: everyone on backend team
│   │                            Triggers: code push → Jenkins builds
│   ├── src/
│   ├── Dockerfile
│   ├── Jenkinsfile            ← defines the CI pipeline for this service
│   └── package.json
│
├── product-service            ← Team: backend developers
│   │                            Access: everyone on backend team
│   ├── src/
│   ├── Dockerfile
│   ├── Jenkinsfile
│   └── package.json
│
├── infrastructure-terraform   ← Team: DevOps / Platform team ONLY
│   │                            Access: restricted, requires PR review
│   │                            Changes: go through Terraform plan review
│   ├── s3-backend/            ← create first, stores all other state files
│   ├── vpc/                   ← VPC, subnets, NAT gateway
│   ├── eks/                   ← EKS cluster, node groups
│   └── iam/                   ← IAM users, roles, policies
│
└── gitops-repo                ← Team: DevOps + read access for everyone
                                  Access: Jenkins writes, ArgoCD reads
                                  This is ArgoCD's single source of truth
    ├── user-service/
    │   ├── deployment.yaml    ← Jenkins updates image tag here
    │   └── service.yaml
    ├── product-service/
    │   ├── deployment.yaml    ← Jenkins updates image tag here
    │   └── service.yaml
    ├── infrastructure/
    │   ├── namespace.yaml
    │   ├── postgres-secret.yaml
    │   └── ingress.yaml
    └── argocd/
        └── applications.yaml  ← ArgoCD app definitions
```

---

## Full End-to-End Flow

```
1. Developer pushes code to user-service repo
        │
        │  GitHub webhook fires → Jenkins
        ▼
2. Jenkins runs user-service/Jenkinsfile:
   ├── Checkout user-service code
   ├── npm install + npm test
   ├── docker build → user-service:42
   ├── trivy scan → no CVEs found
   ├── docker push → ACR/ECR (image stored)
   ├── git clone gitops-repo             ← clones SEPARATE repo
   ├── sed update deployment.yaml        ← changes image tag to :42
   └── git push gitops-repo/main         ← ArgoCD will detect this
        │
        │  ArgoCD polls gitops-repo every 3 minutes (or via webhook)
        ▼
3. ArgoCD detects: user-service/deployment.yaml changed
        │
        │  kubectl apply -f user-service/deployment.yaml
        ▼
4. Kubernetes:
   ├── API Server stores the new Deployment spec
   ├── Deployment Controller creates new ReplicaSet
   ├── Pods created → Kubelet pulls user-service:42 from ACR
   ├── readinessProbe passes → pods marked Ready
   ├── Service updates EndpointSlice (new pods added, old pods removed)
   └── Old pods (user-service:41) terminate gracefully
        │
        ▼
5. Users now served by user-service:42 ✅
```

---

## Who Does What

| Who | Action | Which Repo |
|-----|--------|-----------|
| Backend Developer | Push code | user-service, product-service |
| Jenkins (automated) | Build image, push to ACR, update deployment.yaml | Reads: app repos / Writes: gitops-repo |
| DevOps Engineer | Change K8s config (replicas, resources, env vars) | gitops-repo (PR required) |
| DevOps Engineer | Change infrastructure (new cluster, VPC) | infrastructure-terraform (strict review) |
| ArgoCD (automated) | Detect gitops-repo changes, deploy to AKS | Reads: gitops-repo |
| Developer (emergency rollback) | `git revert` image tag | gitops-repo |

---

## Access Control Per Repo

```
user-service repo:
  Write access: backend team
  Branch protection: PR required for main, CI must pass

product-service repo:
  Write access: backend team
  Branch protection: PR required for main, CI must pass

infrastructure-terraform repo:
  Write access: DevOps team only
  Branch protection: PR required, 2 reviewers, terraform plan output in PR

gitops-repo:
  Write access: Jenkins service account (automated), DevOps team
  Read access: all developers (they can see what's deployed)
  Branch protection: PR required for manual changes
  Note: Jenkins bypasses PR for automated image tag updates (it's just a tag change)
```

---

## Local Development

Each service has its own docker-compose for local testing.
No need to clone all repos — developers only clone their service repo.

```bash
# Developer working on user-service:
git clone github.com/company/user-service
cd user-service
docker compose up   # runs user-service + postgres locally

# Test
curl http://localhost:3000/users
```

---

## Setup Order (one time)

```bash
# 1. Create Terraform state storage FIRST
cd infrastructure-terraform/s3-backend
terraform init && terraform apply

# 2. Create VPC
cd ../vpc
terraform init && terraform apply

# 3. Create EKS cluster
cd ../eks
terraform init && terraform apply

# 4. Connect kubectl to cluster
aws eks update-kubeconfig --name microservices-eks --region us-east-1

# 5. Install ArgoCD in cluster
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 6. Register all applications in ArgoCD (one command)
kubectl apply -f gitops-repo/argocd/applications.yaml
# ArgoCD now watches gitops-repo and deploys everything automatically

# 7. Setup Jenkins jobs
# Create one Pipeline job per service, point to each app repo's Jenkinsfile
# Add credentials: GitHub token (github-credentials), ACR key (acr-credentials)
```
