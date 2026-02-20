#!/usr/bin/env bash
# install-mac.sh — CarClaw Bridge installer for macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-mac.sh | bash
#
# Or clone and run:
#   git clone https://github.com/hankh95/carclaw-bridge-installer.git
#   cd carclaw-bridge-installer
#   ./install-mac.sh
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

# macOS-specific services
AVAILABLE_SERVICES=("telegram" "whatsapp" "imessage")

PLIST_NAME="com.congruentsys.carclaw-bridge"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

SERVICE_NAME="$PLIST_NAME"
START_CMD="launchctl load $PLIST_PATH"
STOP_CMD="launchctl unload $PLIST_PATH"
STATUS_CMD="launchctl list | grep carclaw"
LOGS_CMD="tail -f /tmp/carclaw-bridge.log"

# ─── Uninstall ───────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    step "Uninstalling CarClaw Bridge"

    if [[ -f "$PLIST_PATH" ]]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm "$PLIST_PATH"
        ok "Removed launchd service"
    else
        skip "No launchd service found"
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
echo "  ╔═══════════════════════════════════════╗"
echo "  ║   CarClaw Bridge Installer — macOS    ║"
echo "  ║   Congruent Systems PBC               ║"
echo "  ╚═══════════════════════════════════════╝"
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

    info "Installing Node.js via Homebrew..."

    # Install Homebrew if missing
    if ! has_command brew; then
        info "Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add brew to PATH for this session
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    fi

    brew install node
    ok "Node.js installed: $(node --version)"
fi

# ─── Bridge Code ─────────────────────────────────────────────────────────────

clone_or_update_bridge

# ─── npm Dependencies ────────────────────────────────────────────────────────

install_npm_deps

# ─── .env Setup ──────────────────────────────────────────────────────────────

init_env

# ─── Service Selection ───────────────────────────────────────────────────────

if prompt_services; then
    for svc in "${SELECTED_SERVICES[@]}"; do
        case "$svc" in
            telegram) setup_telegram ;;
            whatsapp) setup_whatsapp ;;
            imessage) setup_imessage ;;
        esac
    done
fi

# ─── Agent Roster ───────────────────────────────────────────────────────────

setup_agents

# ─── Tailscale ───────────────────────────────────────────────────────────────

setup_tailscale

# ─── launchd Service ────────────────────────────────────────────────────────

step "System Service (launchd)"

if [[ -f "$PLIST_PATH" ]]; then
    skip "launchd plist already exists"
    echo -n "Recreate it? (y/N): "
    read -r yn
    if [[ ! "$yn" =~ ^[Yy] ]]; then
        info "Keeping existing service"
    else
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        create_launchd_plist
    fi
else
    create_launchd_plist
fi

# ─── Health Check ────────────────────────────────────────────────────────────

health_check

# ─── Start Service ───────────────────────────────────────────────────────────

step "Starting Bridge"

echo -n "Start the bridge now? (Y/n): "
read -r yn
if [[ ! "$yn" =~ ^[Nn] ]]; then
    launchctl load "$PLIST_PATH"
    sleep 2

    if launchctl list | grep -q "$PLIST_NAME"; then
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
# macOS-specific functions
# ═══════════════════════════════════════════════════════════════════════════════

function setup_imessage() {
    step "iMessage Setup (BlueBubbles)"

    if detect_imessage_enabled; then
        skip "iMessage already enabled"
        return 0
    fi

    echo "iMessage bridging requires BlueBubbles running on this Mac."
    echo ""

    # Check if BlueBubbles is installed
    if [[ -d "/Applications/BlueBubbles.app" ]]; then
        ok "BlueBubbles is installed"
    else
        echo -n "Install BlueBubbles? (Y/n): "
        read -r yn
        if [[ ! "$yn" =~ ^[Nn] ]]; then
            if has_command brew; then
                info "Installing via Homebrew..."
                brew install --cask bluebubbles
                ok "BlueBubbles installed"
            else
                echo "Download BlueBubbles from: https://bluebubbles.app/downloads"
                echo -n "Press Enter when installed..."
                read -r
            fi
        else
            info "Skipping BlueBubbles install — you can install it later"
            return 0
        fi
    fi

    echo ""
    echo "BlueBubbles setup:"
    echo "  1. Open BlueBubbles and complete the initial setup"
    echo "  2. Set a server password in BlueBubbles settings"
    echo "  3. Make sure Messages.app is signed into iCloud"
    echo ""
    echo -n "Enter your BlueBubbles server password: "
    read -rs bb_password
    echo ""

    if [[ -z "$bb_password" ]]; then
        warn "No password entered — skipping iMessage"
        return 0
    fi

    # Test connection
    local bb_url="${BLUEBUBBLES_URL:-http://localhost:1234}"
    info "Testing connection to BlueBubbles at $bb_url..."

    local response
    response=$(curl -s "${bb_url}/api/v1/server/info?password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$bb_password'))")" 2>/dev/null || echo "")

    if echo "$response" | grep -q '"status":200'; then
        ok "BlueBubbles connection successful"
        set_env "IMESSAGE_ENABLED" "true"
        set_env "BLUEBUBBLES_URL" "$bb_url"
        set_env "BLUEBUBBLES_PASSWORD" "$bb_password"
        ok "iMessage configured"

        # The bridge will auto-register its webhook on startup
        info "The bridge will register its webhook with BlueBubbles on startup"
    else
        fail "Could not reach BlueBubbles. Make sure it's running."
        echo "You can configure iMessage later by editing $ENV_FILE"
    fi
}

function create_launchd_plist() {
    local node_path
    node_path=$(which node)

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
        <string>${node_path}</string>
        <string>-r</string>
        <string>dotenv/config</string>
        <string>server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${BRIDGE_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/carclaw-bridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/carclaw-bridge.log</string>
</dict>
</plist>
PLIST

    ok "Created launchd plist at $PLIST_PATH"
}

function _install_tailscale() {
    if has_command brew; then
        info "Installing Tailscale via Homebrew..."
        brew install --cask tailscale
        ok "Tailscale installed"
    else
        echo "Download Tailscale from: https://tailscale.com/download/mac"
        echo -n "Press Enter when installed..."
        read -r
    fi
}
