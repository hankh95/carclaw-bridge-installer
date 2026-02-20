#!/usr/bin/env bash
# install-agent-debian.sh — CarClaw Agent Daemon installer for Debian/Ubuntu.
#
# Installs the agent-daemon only (no bridge, no messaging services).
# The daemon connects to an existing CarClaw bridge on your network
# and responds to CarClaw messages from that machine's project context.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-agent-debian.sh | bash
#
# Or clone and run:
#   git clone https://github.com/hankh95/carclaw-bridge-installer.git
#   cd carclaw-bridge-installer && ./install-agent-debian.sh

set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

step()  { echo -e "\n${BOLD}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; }
info()  { echo -e "  $1"; }

# ─── Config ──────────────────────────────────────────────────────────────────

BRIDGE_REPO="https://github.com/hankh95/carclaw-bridge.git"
AGENT_DIR="${HOME}/carclaw-bridge"
ENV_FILE="${AGENT_DIR}/.env"

SERVICE_NAME="carclaw-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ─── Uninstall ────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    step "Uninstalling CarClaw Agent Daemon"
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        sudo systemctl stop "$SERVICE_NAME"
        ok "Stopped service"
    fi
    if [[ -f "$SERVICE_FILE" ]]; then
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
        ok "Removed systemd service"
    fi
    echo -n "Also remove agent files at $AGENT_DIR? (y/N): "
    read -r yn
    [[ "$yn" =~ ^[Yy] ]] && rm -rf "$AGENT_DIR" && ok "Removed agent directory"
    ok "Uninstall complete"
    exit 0
fi

# ─── Banner ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║  CarClaw Agent Daemon — Debian/Ubuntu ║"
echo "  ║  Congruent Systems PBC                ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"
echo "  Connects this machine to an existing CarClaw bridge"
echo "  so it can respond to messages from the CarClaw app."
echo ""

# ─── Node.js ─────────────────────────────────────────────────────────────────

step "Node.js"

NODE_OK=false
if command -v node &>/dev/null; then
    NODE_VER=$(node --version | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if [[ "$NODE_MAJOR" -ge 18 ]]; then
        ok "Node.js v${NODE_VER}"
        NODE_OK=true
    else
        warn "Node.js v${NODE_VER} found but v18+ required"
    fi
fi

if [[ "$NODE_OK" == "false" ]]; then
    info "Installing Node.js 20 via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    ok "Node.js installed: $(node --version)"
fi

# ─── Clone / Update Agent Code ───────────────────────────────────────────────

step "Agent Code"

if [[ -d "$AGENT_DIR/.git" ]]; then
    info "Updating existing installation..."
    git -C "$AGENT_DIR" pull --ff-only 2>/dev/null && ok "Updated to latest" || warn "Could not pull — using existing version"
else
    info "Cloning carclaw-bridge..."
    git clone "$BRIDGE_REPO" "$AGENT_DIR"
    ok "Cloned to $AGENT_DIR"
fi

# ─── npm Dependencies ────────────────────────────────────────────────────────

step "npm Dependencies"
cd "$AGENT_DIR"
npm install --silent
ok "Dependencies installed"

# ─── Claude CLI ──────────────────────────────────────────────────────────────

step "Claude CLI"

CLAUDE_BIN=""
if command -v claude &>/dev/null; then
    CLAUDE_BIN=$(command -v claude)
    ok "Found claude at $CLAUDE_BIN"
elif [[ -f "${AGENT_DIR}/node_modules/.bin/claude" ]]; then
    CLAUDE_BIN="${AGENT_DIR}/node_modules/.bin/claude"
    ok "Found claude in node_modules"
else
    warn "claude CLI not found — installing via npm..."
    npm install --save-dev @anthropic-ai/claude-code 2>/dev/null || true
    CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "${AGENT_DIR}/node_modules/.bin/claude")
    if [[ -f "$CLAUDE_BIN" ]]; then
        ok "Claude CLI installed"
    else
        warn "Could not install claude CLI — set CLAUDE_BIN in $ENV_FILE manually"
        CLAUDE_BIN="claude"
    fi
fi

# ─── Configuration ───────────────────────────────────────────────────────────

step "Configuration"

# Load existing values as defaults
load_env_val() { [[ -f "$ENV_FILE" ]] && grep "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo ""; }

DEFAULT_BRIDGE_URL=$(load_env_val "BRIDGE_URL")
DEFAULT_BRIDGE_URL="${DEFAULT_BRIDGE_URL:-ws://m5.local:3100}"

DEFAULT_MACHINE=$(load_env_val "MACHINE_NAME")
DEFAULT_MACHINE="${DEFAULT_MACHINE:-$(hostname -s | tr '[:lower:]' '[:upper:]')}"

DEFAULT_PROJECT=$(load_env_val "PROJECT_DIR")
DEFAULT_PROJECT="${DEFAULT_PROJECT:-${HOME}/Projects/carclaw}"

echo ""
echo "  Bridge URL — WebSocket address of the CarClaw bridge to connect to"
echo -n "  Bridge URL [${DEFAULT_BRIDGE_URL}]: "
read -r input_bridge
BRIDGE_URL="${input_bridge:-$DEFAULT_BRIDGE_URL}"

echo ""
echo "  Machine name — how this agent identifies itself in CarClaw (e.g. DGX, Mini)"
echo -n "  Machine name [${DEFAULT_MACHINE}]: "
read -r input_machine
MACHINE_NAME="${input_machine:-$DEFAULT_MACHINE}"

echo ""
echo "  Project directory — the repo Claude will work in when responding"
echo -n "  Project dir [${DEFAULT_PROJECT}]: "
read -r input_project
PROJECT_DIR="${input_project:-$DEFAULT_PROJECT}"

# Write .env
cat > "$ENV_FILE" << ENV
# CarClaw Agent Daemon configuration
# Generated by install-agent-debian.sh

BRIDGE_URL=${BRIDGE_URL}
MACHINE_NAME=${MACHINE_NAME}
PROJECT_DIR=${PROJECT_DIR}
CLAUDE_BIN=${CLAUDE_BIN}
CLAUDECODE=
ENV

ok "Configuration saved to $ENV_FILE"

# ─── systemd Service ─────────────────────────────────────────────────────────

step "System Service (systemd)"

NODE_PATH=$(command -v node)
CURRENT_USER=$(whoami)

sudo tee "$SERVICE_FILE" > /dev/null << SERVICE
[Unit]
Description=CarClaw Agent Daemon (${MACHINE_NAME})
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${AGENT_DIR}
ExecStart=${NODE_PATH} agent-daemon.js
Restart=on-failure
RestartSec=5

Environment=BRIDGE_URL=${BRIDGE_URL}
Environment=MACHINE_NAME=${MACHINE_NAME}
Environment=PROJECT_DIR=${PROJECT_DIR}
Environment=CLAUDE_BIN=${CLAUDE_BIN}
Environment=CLAUDECODE=

StandardOutput=append:/tmp/carclaw-agent.log
StandardError=append:/tmp/carclaw-agent.log

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
ok "Systemd service created and enabled"

# ─── Start ───────────────────────────────────────────────────────────────────

step "Starting Agent Daemon"

echo -n "Start the agent daemon now? (Y/n): "
read -r yn
if [[ ! "$yn" =~ ^[Nn] ]]; then
    sudo systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "Agent daemon is running"
    else
        warn "Daemon may not have started — check: tail -f /tmp/carclaw-agent.log"
        warn "Or: sudo systemctl status $SERVICE_NAME"
    fi
else
    info "Start manually: sudo systemctl start $SERVICE_NAME"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  CarClaw Agent Daemon installed!${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Machine:    ${MACHINE_NAME}"
echo "  Bridge:     ${BRIDGE_URL}"
echo "  Project:    ${PROJECT_DIR}"
echo "  Logs:       tail -f /tmp/carclaw-agent.log"
echo "  Status:     sudo systemctl status ${SERVICE_NAME}"
echo "  Stop:       sudo systemctl stop ${SERVICE_NAME}"
echo "  Uninstall:  $(basename "$0") --uninstall"
echo ""
echo "  ${YELLOW}Note:${NC} The CarClaw app connects to the bridge at ${BRIDGE_URL}."
echo "  This machine (${MACHINE_NAME}) will respond to messages routed to it."
echo ""
