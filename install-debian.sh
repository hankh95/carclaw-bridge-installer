#!/usr/bin/env bash
# install-debian.sh — CarClaw Bridge installer for Debian/Ubuntu.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-debian.sh | bash
#
# Or clone and run:
#   git clone https://github.com/hankh95/carclaw-bridge-installer.git
#   cd carclaw-bridge-installer
#   ./install-debian.sh
#
# Flags:
#   --uninstall    Remove bridge service and optionally delete bridge files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library (works from clone or standalone)
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Download common.sh if running via curl pipe
    COMMON_URL="https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/lib/common.sh"
    TMPDIR_INSTALL=$(mktemp -d)
    curl -fsSL "$COMMON_URL" -o "$TMPDIR_INSTALL/common.sh"
    source "$TMPDIR_INSTALL/common.sh"
fi

# Debian-specific: no iMessage
AVAILABLE_SERVICES=("telegram" "whatsapp")

SERVICE_FILE="/etc/systemd/system/carclaw-bridge.service"
SERVICE_NAME="carclaw-bridge"
START_CMD="sudo systemctl start carclaw-bridge"
STOP_CMD="sudo systemctl stop carclaw-bridge"
STATUS_CMD="systemctl status carclaw-bridge"
LOGS_CMD="journalctl -u carclaw-bridge -f"

# ─── Uninstall ───────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    step "Uninstalling CarClaw Bridge"

    if [[ -f "$SERVICE_FILE" ]]; then
        sudo systemctl stop carclaw-bridge 2>/dev/null || true
        sudo systemctl disable carclaw-bridge 2>/dev/null || true
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
        ok "Removed systemd service"
    else
        skip "No systemd service found"
    fi

    echo -n "Also remove bridge code at $BRIDGE_DIR? (y/N): "
    read -r yn
    if [[ "$yn" =~ ^[Yy] ]]; then
        rm -rf "$BRIDGE_DIR"
        ok "Removed bridge directory"
    fi

    ok "Uninstall complete"
    exit 0
fi

# ─── Banner ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   CarClaw Bridge Installer — Debian/Ubuntu   ║"
echo "  ║   Congruent Systems PBC                      ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── State Detection ────────────────────────────────────────────────────────

show_state

# ─── Node.js ─────────────────────────────────────────────────────────────────

step "Node.js"

if detect_node && [[ "$NODE_MAJOR" -ge 18 ]]; then
    ok "Node.js $NODE_VERSION (meets minimum v18)"
else
    if detect_node; then
        warn "Node.js $NODE_VERSION found but v18+ required"
    fi

    info "Installing Node.js 20.x via NodeSource..."

    # Install NodeSource repo
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq nodejs
    ok "Node.js installed: $(node --version)"
fi

# ─── System Dependencies ────────────────────────────────────────────────────

step "System Dependencies"

info "Installing required packages..."

# Puppeteer dependencies (for WhatsApp) + avahi for Bonjour
PACKAGES=(
    git
    avahi-daemon
    avahi-utils
    # Puppeteer / Chromium dependencies
    libgconf-2-4
    libatk1.0-0
    libatk-bridge2.0-0
    libgdk-pixbuf2.0-0
    libgtk-3-0
    libx11-6
    libxcb1
    libxss1
    libxtst6
    libxcomposite1
    libxdamage1
    libxrandr2
    libpangocairo-1.0-0
    libnss3
    libgbm1
    libasound2
)

# Filter to only packages not yet installed
TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    sudo apt-get install -y -qq "${TO_INSTALL[@]}" 2>/dev/null || {
        warn "Some packages may not be available — continuing anyway"
    }
    ok "System packages installed"
else
    skip "All system packages already installed"
fi

# Make sure avahi is running for Bonjour discovery
if systemctl is-active --quiet avahi-daemon; then
    ok "avahi-daemon is running"
else
    info "Starting avahi-daemon..."
    sudo systemctl enable avahi-daemon
    sudo systemctl start avahi-daemon
    ok "avahi-daemon started"
fi

# ─── Avahi Service for CarClaw Discovery ─────────────────────────────────────

AVAHI_SERVICE_FILE="/etc/avahi/services/carclaw-bridge.service"
if [[ ! -f "$AVAHI_SERVICE_FILE" ]]; then
    info "Registering Bonjour service for network discovery..."
    sudo tee "$AVAHI_SERVICE_FILE" > /dev/null << AVAHI
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">CarClaw Bridge (%h)</name>
  <service>
    <type>_carclaw._tcp</type>
    <port>3100</port>
    <txt-record>version=1</txt-record>
  </service>
</service-group>
AVAHI
    sudo systemctl restart avahi-daemon
    ok "Bonjour service registered (_carclaw._tcp)"
else
    skip "Bonjour service already registered"
fi

# ─── Bridge Code ─────────────────────────────────────────────────────────────

clone_or_update_bridge

# ─── npm Dependencies ────────────────────────────────────────────────────────

install_npm_deps

# ─── .env Setup ──────────────────────────────────────────────────────────────

init_env

# ─── Service Selection ───────────────────────────────────────────────────────

echo ""
info "iMessage is not available on Linux — use a Mac for iMessage bridging."
echo ""

if prompt_services; then
    for svc in "${SELECTED_SERVICES[@]}"; do
        case "$svc" in
            telegram) setup_telegram ;;
            whatsapp) setup_whatsapp ;;
        esac
    done
fi

# ─── Agent Roster ───────────────────────────────────────────────────────────

setup_agents

# ─── Tailscale ───────────────────────────────────────────────────────────────

setup_tailscale

# ─── systemd Service ────────────────────────────────────────────────────────

step "System Service (systemd)"

if [[ -f "$SERVICE_FILE" ]]; then
    skip "systemd service already exists"
    echo -n "Recreate it? (y/N): "
    read -r yn
    if [[ ! "$yn" =~ ^[Yy] ]]; then
        info "Keeping existing service"
    else
        sudo systemctl stop carclaw-bridge 2>/dev/null || true
        create_systemd_service
    fi
else
    create_systemd_service
fi

# ─── Health Check ────────────────────────────────────────────────────────────

health_check

# ─── Start Service ───────────────────────────────────────────────────────────

step "Starting Bridge"

echo -n "Start the bridge now? (Y/n): "
read -r yn
if [[ ! "$yn" =~ ^[Nn] ]]; then
    sudo systemctl start carclaw-bridge
    sleep 2

    if systemctl is-active --quiet carclaw-bridge; then
        ok "Bridge is running"
    else
        warn "Bridge may not have started — check: $LOGS_CMD"
    fi
else
    info "Skipped — start manually with: $START_CMD"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

show_summary

# ═══════════════════════════════════════════════════════════════════════════════
# Debian-specific functions
# ═══════════════════════════════════════════════════════════════════════════════

function create_systemd_service() {
    local node_path
    node_path=$(which node)
    local run_user
    run_user=$(whoami)

    sudo tee "$SERVICE_FILE" > /dev/null << SERVICE
[Unit]
Description=CarClaw Multi-Service Bridge
After=network.target avahi-daemon.service

[Service]
Type=simple
User=${run_user}
WorkingDirectory=${BRIDGE_DIR}
ExecStart=${node_path} -r dotenv/config server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICE

    sudo systemctl daemon-reload
    sudo systemctl enable carclaw-bridge
    ok "Created systemd service: carclaw-bridge"
}

function _install_tailscale() {
    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed"
}
