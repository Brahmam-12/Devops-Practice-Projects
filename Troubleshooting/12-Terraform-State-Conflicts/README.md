# Scenario 12: Terraform State Conflicts

## Symptom
- `terraform apply` errors: "Error acquiring the state lock"
- Two engineers applied simultaneously — infrastructure is inconsistent
- State file shows resources that no longer exist
- Plan shows unexpected destroy/recreate of existing resources

---

## 1. Understand the Architecture

```
Terraform state file (terraform.tfstate):
  Records every resource Terraform created.
  Before every plan/apply: reads state → compares with .tf files → calculates diff.

State locking (Azure Blob / S3):
  When apply starts → acquires BLOB LEASE on the state file.
  Other applies wait.
  When apply finishes → releases lease.

Problems:
  Lock stuck     → apply killed mid-run, lease not released
  State drift    → someone deleted a resource manually, state doesn't know
  State corrupt  → two applies ran simultaneously without locking
```

---

## 2. Troubleshooting Strategy

### Step 1: State lock error

```bash
terraform apply
# Error: Error acquiring the state lock
# Error message: storage: service returned error: StatusCode=409
# Lock Info:
#   ID:        abc123
#   Path:      tfstate/prod.tfstate
#   Operation: OperationTypeApply
#   Who:       john@laptop
#   Created:   2026-06-26T09:00:00Z

# Is john still running apply? Check with john.
# If his apply finished/crashed → force unlock
terraform force-unlock abc123

# Azure: break the blob lease manually
az storage blob lease break \
  --account-name tfstateveera \
  --container-name tfstate \
  --blob-name prod.tfstate
```

---

### Step 2: State drift — resource exists in reality but not in state

```bash
# Example: someone created an RG manually in Azure
# Terraform plan shows: No changes (doesn't know about it)
# Or plan tries to create it again and fails

# Import existing resource into state
terraform import azurerm_resource_group.main /subscriptions/xxx/resourceGroups/company-rg

# After import — run plan to confirm state matches reality
terraform plan
# Should show: No changes (infrastructure matches configuration)
```

---

### Step 3: Unexpected destroy in plan

```bash
# Plan shows: will destroy 10 resources you didn't expect

# Step 1: DON'T apply yet
# Step 2: Find out why Terraform thinks they need to be destroyed

# Check if the state file is stale (someone deleted the real resources)
terraform plan -detailed-exitcode
# exitcode 2 = changes detected

# Check what Terraform sees vs what's real
terraform show     # what state thinks exists
terraform refresh  # update state to match real world (CAREFUL)

# If the plan destroys because of a code change:
# Look at git diff — what changed in the .tf files?
git diff HEAD~1 HEAD -- *.tf
```

---

### Step 4: State file corruption (two simultaneous applies)

```bash
# Pull state and inspect
terraform state list      # list all resources in state
terraform state show azurerm_resource_group.main   # inspect one resource

# Compare with what actually exists in Azure
az resource list --resource-group company-rg --output table

# Remove a resource from state that no longer exists
terraform state rm azurerm_resource_group.old-rg

# If state is severely corrupt — restore from previous version (Azure Blob versioning)
az storage blob list \
  --account-name tfstateveera \
  --container-name tfstate \
  --include v \
  --query "[?name=='prod.tfstate']" \
  --output table
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Stuck lock (crashed apply) | Lock created hours ago, no apply running | force-unlock |
| State drift | Plan destroys resources that should stay | terraform import or refresh |
| Two simultaneous applies | State inconsistent, resources duplicated | Restore state from backup version |
| Code change causes destroy | git diff shows removed resource block | Add lifecycle ignore_changes or use moved block |

---

## 5. Prevention

```hcl
# Prevent accidental destroy
resource "azurerm_resource_group" "main" {
  lifecycle {
    prevent_destroy = true    # terraform destroy will error on this resource
  }
}

# Ignore specific attribute changes (don't recreate on tag change)
resource "azurerm_virtual_machine" "main" {
  lifecycle {
    ignore_changes = [tags]
  }
}
```

---

## Interview Answer

**Q: "Terraform apply is failing with a state lock error — what do you do?"**

> "A state lock error means another apply is holding the blob lease. First I check if another pipeline run or engineer is actively applying — if yes, I wait. If the process that held the lock crashed, I use terraform force-unlock with the lock ID from the error message. For state drift — when real resources don't match state — I use terraform import to bring existing resources into state, or terraform state rm to remove resources from state that were deleted outside of Terraform. I always check the plan carefully before any apply and never apply if I see unexpected destroys without understanding why."
