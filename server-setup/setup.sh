#!/bin/bash
# =============================================================================
# Static Sites — Server Setup (run once on QA server)
# =============================================================================
# Sets up the shared static site hosting infrastructure:
#   1. Creates /opt/sites/ directory for site files
#   2. Deploys the static-sites nginx container
#   3. Adds Traefik file provider for per-site routing
#
# Prerequisites:
#   - Traefik running at /opt/traefik/
#   - Docker network 'web' exists
#
# Usage (on the server):
#   bash /opt/apps/static-sites/setup.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_info() { echo -e "  ${CYAN}ℹ${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }

echo -e "${BOLD}Setting up static site hosting${NC}"
echo ""

# --- Verify prerequisites ---------------------------------------------------

if ! docker network inspect web >/dev/null 2>&1; then
    print_error "'web' network not found. Is Traefik running?"
    exit 1
fi
print_success "Docker 'web' network exists"

if [ ! -f /opt/traefik/docker-compose.yml ]; then
    print_error "Traefik not found at /opt/traefik/"
    exit 1
fi
print_success "Traefik found"

# --- Create directories -----------------------------------------------------

mkdir -p /opt/sites
print_success "Created /opt/sites/"

mkdir -p /opt/traefik/dynamic
print_success "Created /opt/traefik/dynamic/"

mkdir -p /opt/apps/static-sites
print_success "Created /opt/apps/static-sites/"

# --- Copy config files -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/docker-compose.yml" /opt/apps/static-sites/
cp "$SCRIPT_DIR/nginx.conf" /opt/apps/static-sites/
print_success "Copied compose and nginx config"

# --- Add file provider to Traefik --------------------------------------------

TRAEFIK_COMPOSE="/opt/traefik/docker-compose.yml"

if grep -q "providers.file" "$TRAEFIK_COMPOSE"; then
    print_info "Traefik file provider already configured"
else
    print_info "Adding file provider to Traefik..."

    # Add the file provider command flags
    sed -i '/--providers.docker.network=web/a\            - "--providers.file.directory=/opt/traefik/dynamic"\n            - "--providers.file.watch=true"' "$TRAEFIK_COMPOSE"

    # Add the dynamic directory volume mount
    sed -i '/traefik_certs:\/letsencrypt/a\            - /opt/traefik/dynamic:/opt/traefik/dynamic:ro' "$TRAEFIK_COMPOSE"

    print_success "Added file provider config to Traefik"
    print_info "Traefik will be restarted to pick up changes"

    # Restart Traefik
    cd /opt/traefik && docker compose up -d
    print_success "Traefik restarted"
fi

# --- Start static-sites container --------------------------------------------

cd /opt/apps/static-sites
docker compose up -d
print_success "static-sites container started"

# --- Verify ------------------------------------------------------------------

echo ""
if docker ps --filter "name=static-sites" --format "{{.Status}}" | grep -q "Up"; then
    print_success "static-sites container is running"
else
    print_error "static-sites container failed to start"
    docker logs static-sites 2>&1 | tail -5
    exit 1
fi

echo ""
echo -e "${BOLD}Setup complete.${NC}"
echo ""
echo "  Deploy a site by pushing to a repo created from the static-site-template."
echo "  Or manually:"
echo "    mkdir -p /opt/sites/my-site"
echo "    echo '<h1>Hello</h1>' > /opt/sites/my-site/index.html"
echo "    # Then create /opt/traefik/dynamic/my-site.yml (see template README)"
echo ""
