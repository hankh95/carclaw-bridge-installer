#!/usr/bin/env bash
# install-agent-mac.sh — CarClaw Agent Daemon installer for macOS.
#
# Installs the agent-daemon only (no bridge, no messaging services).
# The daemon connects to an existing CarClaw bridge on your network
# and responds to CarClaw messages from that machine's project context.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-agent-mac.sh | bash
#
# Or clone and run:
#   git clone https://github.com/hankh95/carclaw-bridge-installer.git
#   cd carclaw-bridge-installer && ./install-agent-mac.sh

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

PLIST_NAME="com.congruentsys.carclaw-agent"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"

# ─── Uninstall ────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    step "Uninstalling CarClaw Agent Daemon"
    if [[ -f "$PLIST_PATH" ]]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm "$PLIST_PATH"
        ok "Removed launchd service"
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
echo "  ║  CarClaw Agent Daemon — macOS         ║"
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
    info "Installing Node.js via Homebrew..."
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
        [[ -f /usr/local/bin/brew ]]   && eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew install node
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
    npm install -g @anthropic-ai/claude-code 2>/dev/null || npm install --save-dev @anthropic-ai/claude-code
    CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "${AGENT_DIR}/node_modules/.bin/claude")
    ok "Claude CLI installed"
fi

# ─── Configuration ───────────────────────────────────────────────────────────

step "Configuration"

# Load existing values as defaults
load_env_val() { [[ -f "$ENV_FILE" ]] && grep "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo ""; }

DEFAULT_BRIDGE_URL=$(load_env_val "BRIDGE_URL")
DEFAULT_BRIDGE_URL="${DEFAULT_BRIDGE_URL:-ws://m5.local:3100}"

DEFAULT_MACHINE=$(load_env_val "MACHINE_NAME")
if [[ -z "$DEFAULT_MACHINE" ]]; then
    DEFAULT_MACHINE=$(scutil --get ComputerName 2>/dev/null | tr ' ' '-' || hostname -s)
fi

DEFAULT_PROJECT=$(load_env_val "PROJECT_DIR")
DEFAULT_PROJECT="${DEFAULT_PROJECT:-${HOME}/Projects/carclaw}"

echo ""
echo "  Bridge URL — WebSocket address of the CarClaw bridge to connect to"
echo -n "  Bridge URL [${DEFAULT_BRIDGE_URL}]: "
read -r input_bridge
BRIDGE_URL="${input_bridge:-$DEFAULT_BRIDGE_URL}"

echo ""
echo "  Machine name — how this agent identifies itself in CarClaw (e.g. Mini, DGX)"
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
# Generated by install-agent-mac.sh

BRIDGE_URL=${BRIDGE_URL}
MACHINE_NAME=${MACHINE_NAME}
PROJECT_DIR=${PROJECT_DIR}
CLAUDE_BIN=${CLAUDE_BIN}
CLAUDECODE=
ENV

ok "Configuration saved to $ENV_FILE"

# ─── launchd Service ─────────────────────────────────────────────────────────

step "System Service (launchd)"

NODE_PATH=$(command -v node)

if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    info "Replacing existing service..."
fi

mkdir -p "$(dirname "$PLIST_PATH")"
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_PATH}</string>
        <string>agent-daemon.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${AGENT_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>BRIDGE_URL</key>
        <string>${BRIDGE_URL}</string>
        <key>MACHINE_NAME</key>
        <string>${MACHINE_NAME}</string>
        <key>PROJECT_DIR</key>
        <string>${PROJECT_DIR}</string>
        <key>CLAUDE_BIN</key>
        <string>${CLAUDE_BIN}</string>
        <key>CLAUDECODE</key>
        <string></string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/carclaw-agent.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/carclaw-agent.log</string>
</dict>
</plist>
PLIST

ok "Created launchd plist at $PLIST_PATH"

# ─── Start ───────────────────────────────────────────────────────────────────

step "Starting Agent Daemon"

echo -n "Start the agent daemon now? (Y/n): "
read -r yn
if [[ ! "$yn" =~ ^[Nn] ]]; then
    launchctl load "$PLIST_PATH"
    sleep 2
    if launchctl list | grep -q "$PLIST_NAME"; then
        ok "Agent daemon is running"
    else
        warn "Daemon may not have started — check: tail -f /tmp/carclaw-agent.log"
    fi
else
    info "Start manually: launchctl load $PLIST_PATH"
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
echo "  Stop:       launchctl unload $PLIST_PATH"
echo "  Uninstall:  $(basename "$0") --uninstall"
echo ""
echo "  ${YELLOW}Note:${NC} The CarClaw app connects to the bridge at ${BRIDGE_URL}."
echo "  This machine (${MACHINE_NAME}) will respond to messages routed to it."
echo ""
