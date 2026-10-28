# ═══════════════════════════════════════════════════════════════
# QRForge Frontend — Multi-Stage Dockerfile
# ═══════════════════════════════════════════════════════════════
#
# WHY MULTI-STAGE?
#   Stage 1 (builder): Full Node environment to install ALL npm packages
#   including devDependencies used by build tools.
#   Stage 2 (runtime): Fresh, minimal Node image — ONLY the production
#   node_modules and application code are copied over.
#   Result: The final image is ~60-70% smaller because it never includes:
#     • npm cache (~200 MB in layer)
#     • devDependencies (e.g., Jest, ESLint, TypeScript compiler)
#     • Intermediate build artifacts
#     • APK build tools needed to compile native addons

# ── Stage 1: Dependency builder ────────────────────────────────
FROM node:20-alpine AS builder

# Install only dependencies needed to compile native npm addons
# (canvas, sharp, etc. may need build tools — qrcode doesn't, but
#  this is good practice for production pipelines)
RUN apk add --no-cache python3 make g++

WORKDIR /build

# Copy manifests first — Docker layer cache means npm ci only reruns
# when package.json or package-lock.json actually changes
COPY package.json package-lock.json* ./

# --omit=dev skips devDependencies; --prefer-offline uses cache where possible
RUN npm ci --omit=dev --prefer-offline

# ── Stage 2: Production runtime ────────────────────────────────
FROM node:20-alpine AS runtime

# Metadata labels (OCI standard)
LABEL org.opencontainers.image.title="QRForge Frontend" \
      org.opencontainers.image.description="QR code generator web service" \
      org.opencontainers.image.version="1.0.0"

# Create a non-root user for security (UID/GID 1001 matching k8s securityContext)
RUN addgroup -g 1001 -S qrforge && adduser -u 1001 -S -G qrforge qrforge

WORKDIR /app

# Copy ONLY what the production server needs:
#   - node_modules from builder (no npm cache, no devDeps)
#   - Application source files
#   - Static frontend assets
COPY --from=builder /build/node_modules ./node_modules
COPY server.js       ./
COPY templates.json  ./
COPY public/         ./public/

# Ensure the non-root user owns the app files
RUN chown -R qrforge:qrforge /app

# Drop to non-root
USER qrforge

# Document the exposed port (does NOT publish it — that's docker run -p)
EXPOSE 3000

# Environment defaults
ENV NODE_ENV=production \
    PORT=3000 \
    LOG_LEVEL=silent

# Docker HEALTHCHECK — Docker daemon will mark the container unhealthy
# if this fails, enabling Swarm/Compose to restart it.
# In Kubernetes we use readinessProbe/livenessProbe in the manifest instead,
# but having HEALTHCHECK here keeps docker-compose healthcheck working too.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

# Start the server
CMD ["node", "server.js"]
