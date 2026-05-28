# syntax=docker/dockerfile:1.7
# Multi-stage, multi-arch Next.js build → distroless runtime
# Target platforms: linux/amd64, linux/arm64

# ─────────────────────────────────────────
# Stage 1: install dependencies
# ─────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy lockfile + manifests only — maximises layer cache reuse
COPY package.json package-lock.json* ./

# Install all deps (dev + prod) needed for the build / fails if it is run on amd64
RUN npm ci --frozen-lockfile --legacy-peer-deps

# ─────────────────────────────────────────
# Stage 2: build
# ─────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_API_URL=http://localhost:8706
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

# next.config.mjs already has output: 'standalone'
RUN npm run build

# ─────────────────────────────────────────
# Stage 3: runtime — distroless (non-root)
# ─────────────────────────────────────────
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runner

WORKDIR /app

# distroless:nonroot runs as UID 65532 — chown at copy time, zero runtime overhead
# standalone output is a self-contained server with its own trimmed node_modules
COPY --from=builder --chown=65532:65532 /app/.next/standalone ./

# Static assets must sit inside the standalone tree at this exact path
COPY --from=builder --chown=65532:65532 /app/.next/static ./.next/static

# Public folder is served by Next.js directly
COPY --from=builder --chown=65532:65532 /app/public ./public

ENV NODE_ENV=production
ENV PORT=3000
# Hostname binding required inside Kubernetes — 0.0.0.0 exposes to the pod network
ENV HOSTNAME=0.0.0.0


EXPOSE 3000

# distroless ENTRYPOINT is already `node`; CMD supplies the script path
CMD ["server.js"]
