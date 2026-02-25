#!/bin/bash
# =============================================================================
# Static Site — QA Setup
# =============================================================================
# Configures GitHub secrets/variables for deploying this static site.
#
# Usage:
#   ./scripts/setup-qa.sh
#
# Prerequisites:
#   - gh CLI installed and authenticated
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}!${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }
print_info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# --- Prerequisites -----------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
    print_error "gh CLI not found. Install from: https://cli.github.com"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    print_error "Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

REPO_NAME=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
SITE_NAME=$(basename "$(git rev-parse --show-toplevel)")

if [ -z "$REPO_NAME" ]; then
    print_error "Could not determine GitHub repo"
    exit 1
fi

echo -e "${BOLD}Static Site QA Setup${NC}"
echo ""
print_info "Repo: $REPO_NAME"
print_info "Site: $SITE_NAME"
print_info "URL:  https://${SITE_NAME}.qa.superposition.systems"
echo ""

# --- Resolve server IP -------------------------------------------------------

HETZNER_REPO="${HETZNER_REPO:-azareljacobs/Hetzner}"
QA_SERVER_IP=$(gh variable get QA_SERVER_IP -R "$HETZNER_REPO" 2>/dev/null || echo "")

if [ -z "$QA_SERVER_IP" ]; then
    print_warning "Could not read QA_SERVER_IP from $HETZNER_REPO"
    echo -n "  Enter server IP: "
    read QA_SERVER_IP
fi

# --- Set GitHub variables/secrets --------------------------------------------

# QA_SERVER_IP (variable)
EXISTING_IP=$(gh variable get QA_SERVER_IP 2>/dev/null || echo "")
if [ "$EXISTING_IP" = "$QA_SERVER_IP" ]; then
    print_success "QA_SERVER_IP already set"
else
    gh variable set QA_SERVER_IP --body "$QA_SERVER_IP"
    print_success "Set QA_SERVER_IP=$QA_SERVER_IP"
fi

# QA_SSH_PRIVATE_KEY (secret)
if gh secret list 2>/dev/null | grep -q "^QA_SSH_PRIVATE_KEY"; then
    print_success "QA_SSH_PRIVATE_KEY already set"
else
    SSH_KEY="$HOME/.ssh/id_ed25519"
    if [ -f "$SSH_KEY" ]; then
        gh secret set QA_SSH_PRIVATE_KEY < "$SSH_KEY"
        print_success "Set QA_SSH_PRIVATE_KEY from $SSH_KEY"
    else
        print_warning "No SSH key found at $SSH_KEY — set manually:"
        print_info "gh secret set QA_SSH_PRIVATE_KEY < /path/to/key"
    fi
fi

echo ""
echo -e "${BOLD}Done.${NC} Push to main to deploy, or run manually:"
echo "  gh workflow run deploy-qa.yml"
echo ""
echo "  Site will be live at: https://${SITE_NAME}.qa.superposition.systems"
echo ""
