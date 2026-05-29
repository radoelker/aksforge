# GitHub Actions Workflows

## CI Pipelines

### [`ci-frontend.yml`](./ci-frontend.yml)
Triggered on push to `dev/**` and PRs targeting `staging` or `main`. Runs ESLint (`eslint .`) and Vitest unit tests for the Next.js frontend. Uses `npm ci --legacy-peer-deps` due to peer dependency conflicts between `class-variance-authority` and TypeScript 6. A passing run is required before any PR can merge.

### [`ci-backend.yml`](./ci-backend.yml)
Triggered on push to `dev/**` and PRs targeting `staging` or `main`. Runs ESLint and Jest unit tests for the Express/TypeScript backend. A passing run is required before any PR can merge.

---

## CD Pipelines — Staging

### [`cd-staging-frontend.yml`](./cd-staging-frontend.yml)
Triggered on push to `staging`. Builds a multi-arch (`amd64`/`arm64`) Docker image with `NEXT_PUBLIC_API_URL` baked in at build time, pushes to ACR with tags `:<git-sha>` and `:staging-latest`, runs a Trivy scan, then updates `k8s/apps/frontend/staging/kustomization.yaml` and commits back to `staging` with `[skip ci]`. ArgoCD auto-syncs to the staging namespace.

### [`cd-staging-backend.yml`](./cd-staging-backend.yml)
Triggered on push to `staging`. Builds a multi-arch Docker image, pushes to ACR with tags `:<git-sha>` and `:staging-latest`, runs a Trivy scan, then updates `k8s/apps/backend/staging/kustomization.yaml` and commits back to `staging` with `[skip ci]`. ArgoCD auto-syncs to the staging namespace.

---

## CD Pipelines — Production

### [`cd-production-frontend.yml`](./cd-production-frontend.yml)
Triggered on push to `main` (or manually via `workflow_dispatch`). Builds a multi-arch image with the production `NEXT_PUBLIC_API_URL` baked in, pushes to ACR with tags `:<git-sha>` and `:latest`, runs a Trivy scan, then updates `k8s/apps/frontend/production/kustomization.yaml` and commits to `main` with `[skip ci]`. ArgoCD syncs and Argo Rollouts begins the canary deployment.

### [`cd-production-backend.yml`](./cd-production-backend.yml)
Triggered on push to `main` (or manually via `workflow_dispatch`). Builds a multi-arch image, pushes to ACR with tags `:<git-sha>` and `:latest`, runs a Trivy scan, then updates `k8s/apps/backend/production/kustomization.yaml` and commits to `main` with `[skip ci]`. ArgoCD syncs and Argo Rollouts begins the canary deployment.

---

## Notes

- All workflows authenticate to ACR using admin credentials (`ACR_USERNAME` / `ACR_PASSWORD` secrets). Switch to OIDC after Step 16 (ARC runners).
- Multi-arch builds require `NODE_OPTIONS=--jitless` to prevent QEMU SEGFAULT on ARM64 emulation.
- Production CD commits use `git pull --rebase origin main` before pushing to handle race conditions when frontend and backend workflows trigger simultaneously.
- `[skip ci]` on bot commits prevents infinite CI loops.
