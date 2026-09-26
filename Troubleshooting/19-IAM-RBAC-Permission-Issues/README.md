# Scenario 19: IAM / RBAC Permission Issues

## Symptom
- AWS: "AccessDenied" or "is not authorized to perform"
- Azure: "AuthorizationFailed" or "does not have authorization to perform action"
- Kubernetes: "Forbidden" — User cannot list/get/create resources
- CI/CD pipeline cannot deploy because of permission error
- App cannot read from S3 / Azure Blob

---

## 1. Understand the Architecture

```
AWS IAM:
  Principal (user/role/service) + Policy (allow/deny actions on resources)
  EC2 uses Instance Role → app on EC2 inherits those permissions
  EKS pod uses IAM Role for Service Account (IRSA) → pod-level permissions

Azure RBAC:
  Principal (user/SP/managed identity) + Role (Owner/Contributor/Reader/custom)
  Scope: subscription → resource group → resource
  VM uses Managed Identity → app on VM inherits those permissions

Kubernetes RBAC:
  ServiceAccount → ClusterRole/Role (what resources, what verbs)
                 → ClusterRoleBinding/RoleBinding (links SA to role)
  Pipeline uses ServiceAccount to deploy
```

---

## 2. Troubleshooting Strategy

### Step 1: Read the exact error

```
AWS:   "sts:AssumeRole is not authorized for resource arn:aws:iam::123:role/myrole"
       → Role trust policy doesn't allow this principal to assume it

       "s3:GetObject is not authorized to perform: s3:GetObject on resource arn:aws:s3:::mybucket/file.txt"
       → IAM policy missing s3:GetObject for this bucket

Azure: "The client 'xxx' with object id 'yyy' does not have authorization to perform action
        'Microsoft.Storage/storageAccounts/read'"
       → Missing role assignment for that action

Kubernetes: "User "system:serviceaccount:production:myapp" cannot list resource "secrets"
             in namespace "production""
            → ServiceAccount myapp in production ns missing role with secrets list permission
```

---

### Step 2: AWS — Check and simulate permissions

```bash
# What permissions does this role have?
aws iam list-attached-role-policies --role-name my-role
aws iam list-role-policies --role-name my-role   # inline policies

# Simulate a specific action (does not actually perform it)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123:role/my-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::mybucket/myfile.txt

# Output:
# EvalDecision: allowed    ← will work
# EvalDecision: implicitDeny ← no policy grants it → need to add permission
# EvalDecision: explicitDeny ← a Deny policy is blocking it → find and remove it
```

---

### Step 3: AWS — Check EC2 instance role

```bash
# From inside EC2 — what role am I using?
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
# Returns role name

# What can this role do?
aws sts get-caller-identity   # confirms which role is active
aws s3 ls s3://mybucket       # test S3 access directly
```

---

### Step 4: Azure — Check role assignments

```bash
# What roles does this managed identity / SP have?
az role assignment list \
  --assignee <object-id-or-principal-id> \
  --output table

# Check if role exists at the right scope
az role assignment list \
  --assignee <sp-client-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/myrg \
  --output table

# Add missing role
az role assignment create \
  --assignee <object-id> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<sub-id>/resourceGroups/myrg/providers/Microsoft.Storage/storageAccounts/myaccount
```

---

### Step 5: Kubernetes RBAC — check ServiceAccount permissions

```bash
# What ServiceAccount does this pod use?
kubectl get pod myapp-xxx -n production -o jsonpath='{.spec.serviceAccountName}'

# What can this ServiceAccount do?
kubectl auth can-i list secrets \
  --namespace production \
  --as system:serviceaccount:production:myapp-sa

# Output: yes → allowed, no → not allowed

# Check what ClusterRole/Role is bound to this SA
kubectl get rolebindings -n production | grep myapp-sa
kubectl describe rolebinding myapp-sa-binding -n production

# Add missing permission
kubectl create clusterrole secret-reader \
  --verb=get,list \
  --resource=secrets

kubectl create rolebinding myapp-can-read-secrets \
  --clusterrole=secret-reader \
  --serviceaccount=production:myapp-sa \
  -n production
```

---

### Step 6: Kubernetes — check what the pipeline ServiceAccount can do

```bash
# CI/CD pipeline uses a ServiceAccount to deploy
kubectl auth can-i create deployments \
  --namespace production \
  --as system:serviceaccount:production:pipeline-sa

kubectl auth can-i apply deployments \
  --namespace production \
  --as system:serviceaccount:production:pipeline-sa

# If no → create the missing RoleBinding
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Missing IAM policy | simulate-principal returns implicitDeny | Attach policy with missing action |
| Explicit Deny overriding Allow | simulate returns explicitDeny | Find and remove/narrow the Deny policy |
| Wrong scope (Azure) | Role exists but at subscription, not RG | Add role at correct scope |
| SA has no RoleBinding | `kubectl auth can-i` returns no | Create RoleBinding for the SA |
| Wrong ServiceAccount | Pod using default SA | Set serviceAccountName in pod spec |
| IRSA not configured (EKS) | Pod cannot assume AWS role | Configure IRSA annotation on SA |

---

## Interview Answer

**Q: "App is getting permission denied when accessing S3 / Azure Blob — how do you debug?"**

> "I read the exact error message carefully — it tells me the specific action that was denied and the resource it was denied on. In AWS I use iam simulate-principal-policy to test whether the role has that permission without actually performing the action. It tells me if the result is implicitDeny (no policy grants it) or explicitDeny (a Deny policy is actively blocking it). For Kubernetes RBAC I use kubectl auth can-i to test what a specific ServiceAccount can do. The most common issues are a missing policy attachment, the role existing but at the wrong scope in Azure, or a pod using the default ServiceAccount instead of a custom one with the right permissions."
