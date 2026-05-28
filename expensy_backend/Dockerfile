# syntax=docker/dockerfile:1.7
# Multi-stage, multi-arch Express/TypeScript build → distroless runtime
# Target platforms: linux/amd64, linux/arm64

# ─────────────────────────────────────────
# Stage 1: production dependencies only
# ─────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json* ./

# --omit=dev gives us the exact production node_modules for the final image
RUN npm ci --frozen-lockfile --omit=dev

# ─────────────────────────────────────────
# Stage 2: build (TypeScript → JavaScript)
# ─────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
# Full install (including devDeps) for the TypeScript compiler
RUN npm ci --frozen-lockfile

COPY tsconfig.json ./
COPY src ./src

# Compiles to /app/dist — adjust if outDir differs in your tsconfig.json
RUN npm run build

# ─────────────────────────────────────────
# Stage 3: runtime — distroless (non-root)
# ─────────────────────────────────────────
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runner

WORKDIR /app

# Production node_modules from Stage 1 (no devDeps, no TypeScript toolchain)
COPY --from=deps    --chown=65532:65532 /app/node_modules ./node_modules
# Compiled JavaScript from Stage 2
COPY --from=builder --chown=65532:65532 /app/dist ./dist

ENV NODE_ENV=production
ENV PORT=8706

EXPOSE 8706

# distroless ENTRYPOINT is already `node`
# Adjust dist/server.js if your tsconfig outDir or entry point differs
CMD ["dist/server.js"]
