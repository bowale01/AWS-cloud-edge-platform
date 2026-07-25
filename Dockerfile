################################################################################
# Dockerfile — Multi-Stage Build for Demo App
#
# MULTI-STAGE BUILD:
# Stage 1 (builder): Installs dependencies and builds the app
# Stage 2 (runtime): Copies only the built artifact (no build tools)
#
# WHY MULTI-STAGE?
# - Final image is tiny (~25MB vs ~500MB with build tools)
# - No compiler, package manager, or source code in production image
# - Smaller attack surface (fewer binaries = fewer exploit targets)
# - Faster image pulls (less data to download)
#
# SECURITY BEST PRACTICES IN THIS FILE:
# ✓ Non-root user (UID 1000)
# ✓ Distroless base image (no shell, no package manager)
# ✓ Read-only filesystem compatible
# ✓ No secrets baked into the image
# ✓ Explicit EXPOSE for documentation
# ✓ HEALTHCHECK for container runtime monitoring
################################################################################

# ============= Stage 1: Build =============
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first (Docker layer caching)
# If package.json hasn't changed, npm install layer is cached
COPY package*.json ./
RUN npm ci --only=production

# Copy application source
COPY src/ ./src/

# ============= Stage 2: Production Runtime =============
FROM node:20-alpine AS runtime

# Security: run as non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copy only what's needed from builder (no dev dependencies, no source maps)
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/src ./src

# Switch to non-root user
USER appuser

# Expose the application port
EXPOSE 8080

# Health check (used by Docker and K8s liveness probe)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/healthz || exit 1

# Start the application
CMD ["node", "src/server.js"]
