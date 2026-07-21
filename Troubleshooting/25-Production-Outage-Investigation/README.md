# Scenario 25: Complete End-to-End Production Outage Investigation

## The Most Important Scenario

This is the one that gets asked in every senior DevOps/SRE interview.
It tests everything: your methodology, composure, tooling knowledge, and communication.

---

## The Framework — Always Follow This Order

```
1. ACKNOWLEDGE    → confirm the outage, notify the team, open incident channel
2. SCOPE          → what exactly is down? partial or total? since when?
3. TRIAGE         → find the most likely cause fast (don't fix yet)
4. MITIGATE       → stop the bleeding (rollback, scale out, reroute traffic)
5. INVESTIGATE    → find root cause (after service is restored)
6. RESOLVE        → permanent fix
7. COMMUNICATE    → update stakeholders throughout
8. POST-MORTEM    → write what happened, what we'll change
```

---

## Real Production Outage Walkthrough

### 14:30 — Alert fires: "API returning 503, error rate 100%"

**Immediate actions (first 2 minutes):**

```bash
# 1. Open incident Slack channel: #incident-2026-06-26-1430
# 2. Post: "Investigating 503 errors on API. Lead: @your-name. Updates every 10 min."

# 3. Check scope — what's actually down?
curl https://api.company.com/health           # external API
curl https://internal.company.com/health      # internal services
curl https://admin.company.com/health         # admin panel

# Is it total or partial?
# All returning 503 → something in the path from LB to backend
# Some returning 503 → specific service or database
```

---

### 14:32 — All API endpoints returning 503

```bash
# Check LB target health — this is the fastest way to understand 503
aws elbv2 describe-target-health --target-group-arn arn:...

# Result: ALL targets unhealthy
# Conclusion: app is not responding — problem is in the app layer

# When did this start? Check deployment history
kubectl rollout history deployment/myapp -n production
# Shows: deploy at 14:28 → CORRELATES with outage at 14:30

# First action: ROLLBACK (restore service, investigate later)
kubectl rollout undo deployment/myapp -n production
kubectl rollout status deployment/myapp -n production   # watch recovery
```

---

### 14:35 — Service restored after rollback

```bash
# Confirm service is back
curl https://api.company.com/health   # should return 200

# Notify team: "Service restored at 14:35 via rollback. Investigating root cause."
# Total downtime: 5 minutes

# Now investigate the bad deploy safely
kubectl rollout history deployment/myapp -n production
# Revision 5 = bad deploy, Revision 4 = good (current after rollback)

# Get logs from bad revision (pods were replaced so old logs may be gone)
# Check the CI/CD pipeline logs for revision 5
# Check git log for what changed
git log --oneline v2.2..v2.3    # what commits went into this deploy
```

---

### 14:40 — Root cause investigation

```bash
# What changed in the bad deploy?
git show <commit-hash>
# Changed: database migration script added a new column with NOT NULL constraint
# Without default value → existing rows fail when app reads them → 500 errors
# → Health check returns 500 → LB marks all targets unhealthy → 503

# Reproduce in staging
kubectl apply -f bad-deploy.yaml -n staging
curl https://staging.company.com/health    # should reproduce the 500

# Confirm root cause: migration ran, corrupted existing rows
# Fix: add DEFAULT value to the migration
# Test fix in staging first
```

---

### 15:00 — Permanent fix

```bash
# Fix the migration script
# migration: ALTER TABLE users ADD COLUMN verified BOOLEAN DEFAULT FALSE;
# (was missing DEFAULT FALSE)

# Test in staging
kubectl apply -f fixed-deploy.yaml -n staging
kubectl rollout status deployment/myapp -n staging

# Run integration tests
./run-tests.sh staging

# Deploy to production
kubectl rollout undo deployment/myapp -n production --to-revision=5-fixed
# Or create new revision with the fix
kubectl set image deployment/myapp myapp=myapp:v2.3.1 -n production
kubectl rollout status deployment/myapp -n production
```

---

### 15:15 — Communication & Close

```
Post to #incident channel:
  "Resolved at 15:15.
   Impact: API unavailable 14:30–14:35 (5 minutes).
   Cause: DB migration missing DEFAULT value on new NOT NULL column.
   Fix: Rolled back at 14:35, deployed corrected migration at 15:15.
   Post-mortem scheduled for 2026-06-27 10:00."
```

---

## The Post-Mortem Document

Every production outage needs a written post-mortem within 24 hours:

```markdown
# Incident Report — 2026-06-26 API Outage

## Summary
5-minute API outage (14:30–14:35) caused by a bad database migration deployed at 14:28.

## Timeline
14:28 — Deployment of v2.3 to production (CI/CD pipeline)
14:30 — Alert: error rate 100%, API returning 503
14:32 — Identified: all LB targets unhealthy, correlated with 14:28 deploy
14:35 — Rollback complete, service restored
14:40 — Root cause identified: migration missing DEFAULT value
15:15 — Fixed version v2.3.1 deployed to production

## Root Cause
ALTER TABLE migration added NOT NULL column without DEFAULT.
Existing rows could not be read by the new application code.
Health check endpoint queries the database → returned 500 → LB removed all targets.

## Impact
API: 100% error rate for 5 minutes
Users: ~1,200 users affected (error during the window)
Revenue: ~$800 estimated lost transactions

## What We'll Change
1. Add staging migration test to CI/CD pipeline (run migration + integration test before prod)
2. Add DB migration review checklist to deployment runbook
3. Reduce deploy-to-alert time (was 2 minutes, target <30 seconds)
4. Add automatic rollback trigger: if error rate > 50% for 60 seconds after deploy → auto rollback
```

---

## Key Interview Principles

```
1. COMMUNICATE FIRST — open the incident channel before doing anything
2. SCOPE BEFORE FIXING — know what's broken before touching anything
3. MITIGATE BEFORE INVESTIGATING — restore service, then find root cause
4. ROLLBACK IS ALWAYS FASTEST — if a deploy caused it, roll back
5. ONE PERSON LEADS — others can help but one person coordinates
6. WRITE EVERYTHING DOWN — time, what you checked, what you found, what you changed
7. POST-MORTEM IS BLAMELESS — the goal is system improvement, not finger-pointing
```

---

## Interview Answer

**Q: "Walk me through how you would handle a complete production outage."**

> "First I acknowledge the incident and open a dedicated Slack channel so everyone knows I'm on it. Then I determine scope — is it everything or just one service? Is it recent or has it been happening for a while? I correlate the start time with any recent deployments. If a deploy caused it, I rollback immediately — restore service first, investigate root cause second. Once service is restored I dig into what changed in the bad deploy: git diff, pipeline logs, application logs from the failing pods. I write everything down with timestamps throughout. After resolution I schedule a blameless post-mortem within 24 hours — not to blame anyone but to identify what system changes will prevent this from happening again. The goal is to make the system more resilient, not to find someone to blame."
