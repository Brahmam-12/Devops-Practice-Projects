# Scenario 11: Docker Image Build Failures

## Symptom
- `docker build` returns non-zero exit code
- Pipeline fails at the build stage
- Image missing from registry after "successful" push

---

## 1. Understand the Architecture

```
Dockerfile build stages:
  FROM        → pull base image
  RUN         → execute commands (install packages)
  COPY/ADD    → copy files from host into image
  ENV         → set environment variables
  EXPOSE      → document port
  CMD/ENTRYPOINT → what runs when container starts

Each instruction creates a layer. Build fails if any layer fails.
```

---

## 2. Troubleshooting Strategy

### Step 1: Read the exact failing instruction

```bash
# Build with --no-cache to avoid stale cache hiding real errors
docker build --no-cache -t myapp:test . 2>&1 | tee build.log

# The error line shows which instruction failed:
# Step 4/10: RUN npm install
# npm ERR! 404 Not Found: mypackage@2.0.0
# → package 'mypackage' version 2.0.0 doesn't exist in npm registry
```

---

### Step 2: Common failure — COPY file not found

```bash
# Error: COPY failed: file not found in build context or excluded by .dockerignore

# What to check:
cat .dockerignore    # is the file being excluded?
ls -la               # does the file exist in build context?

# Common mistake: running docker build from wrong directory
docker build -t myapp .          # builds from current dir
docker build -t myapp ./app/     # builds from ./app/ subdirectory
```

---

### Step 3: Package install failures

```bash
# npm install fails
# 1. Check if package exists at that version
npm info mypackage versions

# 2. Private package — needs auth
# Add .npmrc to image:
# //registry.npmjs.org/:_authToken=${NPM_TOKEN}

# pip install fails (Python)
# Use --no-cache-dir to avoid stale cache
RUN pip install --no-cache-dir -r requirements.txt

# apt-get fails
# Always run update before install in same RUN command
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

---

### Step 4: Multi-stage build issues

```bash
# Error: failed to solve: failed to read dockerfile: invalid reference format
# → Stage name typo in FROM xxx AS builder

# Error: COPY --from=builder /app/dist /app/dist: file not found
# → builder stage didn't produce the file (build failed in builder stage)

# Debug: build only the builder stage
docker build --target builder -t myapp:builder .
docker run --rm myapp:builder ls /app/dist   # does the file exist?
```

---

### Step 5: Base image issues

```bash
# Error: pull access denied for myimage, repository does not exist
# → Base image tag wrong, or registry requires auth

# Check image exists
docker pull myregistry.azurecr.io/baseimage:v1.0
# If this fails → login first
az acr login --name myregistry

# Error: no matching manifest for linux/arm64 in the manifest list
# → Building on M1 Mac (arm64) but base image only has amd64
# Fix: specify platform
docker build --platform linux/amd64 -t myapp .
```

---

## 4. Root Cause + Fix

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `file not found` in COPY | .dockerignore excludes file, wrong build context | Fix .dockerignore or build from correct directory |
| `npm ERR 404` | Package version doesn't exist | Fix version in package.json |
| `permission denied` | Running as root but file owned by different user | Add `--chown` to COPY or `chmod` in RUN |
| `no space left on device` | Docker daemon out of disk | `docker system prune -a` |
| `exec format error` | Architecture mismatch | Build with `--platform linux/amd64` |

---

## Interview Answer

**Q: "Docker build is failing in the pipeline — how do you debug?"**

> "I read the exact error from the failing Dockerfile instruction. COPY failures usually mean .dockerignore is too broad or the build context is wrong. Package install failures like npm ERR 404 mean a package or version doesn't exist. For multi-stage builds I build just the first stage separately to confirm it produces the expected output before the COPY --from fails. Architecture mismatches happen when building on Apple Silicon — adding --platform linux/amd64 fixes it. I always reproduce locally with --no-cache first to rule out stale cache masking the real issue."
