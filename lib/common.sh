#!/usr/bin/env bash
# common.sh — Shared functions for CarClaw Bridge installers.

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
step() { echo -e "\n${BOLD}── $1 ──${NC}"; }

# ─── Configuration ───────────────────────────────────────────────────────────

BRIDGE_REPO="https://github.com/hankh95/carclaw-bridge.git"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/carclaw-bridge}"
ENV_FILE="$BRIDGE_DIR/.env"

# ─── State Detection ────────────────────────────────────────────────────────

has_command() { command -v "$1" &>/dev/null; }

detect_node() {
    if has_command node; then
        NODE_VERSION=$(node --version 2>/dev/null || echo "")
        NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
        return 0
    fi
    return 1
}

detect_bridge() {
    [[ -d "$BRIDGE_DIR" && -f "$BRIDGE_DIR/server.js" ]]
}

detect_deps() {
    [[ -d "$BRIDGE_DIR/node_modules" ]]
}

detect_env() {
    [[ -f "$ENV_FILE" ]]
}

detect_telegram_token() {
    if detect_env; then
        grep -q "^TELEGRAM_TOKEN=.\+" "$ENV_FILE" 2>/dev/null
    else
        return 1
    fi
}

detect_imessage_enabled() {
    if detect_env; then
        grep -q "^IMESSAGE_ENABLED=true" "$ENV_FILE" 2>/dev/null
    else
        return 1
    fi
}

detect_whatsapp_enabled() {
    if detect_env; then
        grep -q "^WHATSAPP_ENABLED=true" "$ENV_FILE" 2>/dev/null
    else
        return 1
    fi
}

# ─── Display State ──────────────────────────────────────────────────────────

show_state() {
    step "Current State"

    if detect_node; then
        ok "Node.js $NODE_VERSION"
    else
        fail "Node.js not installed"
    fi

    if detect_bridge; then
        ok "Bridge code at $BRIDGE_DIR"
    else
        fail "Bridge not installed"
    fi

    if detect_deps; then
        ok "npm dependencies installed"
    else
        fail "npm dependencies not installed"
    fi

    if detect_env; then
        ok ".env file exists"
        if detect_telegram_token; then ok "Telegram token set"; else info "Telegram not configured"; fi
        if detect_whatsapp_enabled; then ok "WhatsApp enabled"; else info "WhatsApp not configured"; fi
        if detect_imessage_enabled; then ok "iMessage enabled"; else info "iMessage not configured"; fi
    else
        info "No .env file yet"
    fi
}

# ─── Bridge Setup ────────────────────────────────────────────────────────────

clone_or_update_bridge() {
    step "Bridge Code"

    if detect_bridge; then
        skip "Bridge already cloned at $BRIDGE_DIR"
        info "Pulling latest..."
        (cd "$BRIDGE_DIR" && git pull --ff-only 2>/dev/null) || warn "Could not pull (might have local changes)"
    else
        info "Cloning bridge to $BRIDGE_DIR..."
        git clone "$BRIDGE_REPO" "$BRIDGE_DIR"
        ok "Bridge cloned"
    fi
}

install_npm_deps() {
    step "npm Dependencies"

    if detect_deps; then
        skip "node_modules already exists"
        info "Running npm install to update..."
    else
        info "Installing npm dependencies..."
    fi

    (cd "$BRIDGE_DIR" && npm install)
    ok "Dependencies installed"
}

# ─── Service Selection ───────────────────────────────────────────────────────

# $AVAILABLE_SERVICES should be set by the platform-specific installer
# e.g. ("telegram" "whatsapp" "imessage") on Mac, ("telegram" "whatsapp") on Linux

prompt_services() {
    step "Service Selection"

    echo -e "Which messaging services do you want to connect?"
    echo ""

    local i=1
    for svc in "${AVAILABLE_SERVICES[@]}"; do
        local label=""
        case "$svc" in
            telegram)  label="Telegram (bot in group chats)" ;;
            whatsapp)  label="WhatsApp (via WhatsApp Web)" ;;
            imessage)  label="iMessage (via BlueBubbles, macOS only)" ;;
        esac
        echo -e "  ${BOLD}$i)${NC} $label"
        i=$((i + 1))
    done

    echo ""
    echo -e "Enter numbers separated by spaces (e.g. ${BOLD}1 2${NC}): "
    read -r selections

    SELECTED_SERVICES=()
    for num in $selections; do
        local idx=$((num - 1))
        if [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_SERVICES[@]} ]]; then
            SELECTED_SERVICES+=("${AVAILABLE_SERVICES[$idx]}")
        fi
    done

    if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
        warn "No services selected. You can re-run the installer later."
        return 1
    fi

    echo ""
    ok "Selected: ${SELECTED_SERVICES[*]}"
}

# ─── Telegram Setup ─────────────────────────────────────────────────────────

setup_telegram() {
    step "Telegram Setup"

    if detect_telegram_token; then
        skip "Telegram token already configured"
        return 0
    fi

    echo -e "To set up Telegram, you need a bot token from ${BOLD}@BotFather${NC}."
    echo ""
    echo "  1. Open Telegram and message @BotFather"
    echo "  2. Send /newbot and follow the prompts"
    echo "  3. Copy the bot token"
    echo "  4. Send /setprivacy → select your bot → Disable"
    echo "     (so the bot can see all group messages)"
    echo ""
    echo -n "Paste your bot token: "
    read -r token

    if [[ -z "$token" ]]; then
        warn "No token entered — skipping Telegram"
        return 0
    fi

    # Validate token
    info "Validating token..."
    local response
    response=$(curl -s "https://api.telegram.org/bot${token}/getMe" 2>/dev/null || echo "")

    if echo "$response" | grep -q '"ok":true'; then
        local bot_name
        bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        ok "Token valid — bot: @${bot_name}"
        set_env "TELEGRAM_TOKEN" "$token"
    else
        fail "Token validation failed. Check the token and try again."
        return 0
    fi
}

# ─── WhatsApp Setup ─────────────────────────────────────────────────────────

setup_whatsapp() {
    step "WhatsApp Setup"

    if detect_whatsapp_enabled; then
        skip "WhatsApp already enabled"
        return 0
    fi

    echo -e "${YELLOW}Note:${NC} WhatsApp Web linking may be blocked by Meta."
    echo "If QR scanning doesn't work, use Telegram instead."
    echo ""
    echo -n "Enable WhatsApp? (y/N): "
    read -r yn

    if [[ "$yn" =~ ^[Yy] ]]; then
        set_env "WHATSAPP_ENABLED" "true"
        ok "WhatsApp enabled — QR code will appear when bridge starts"
        info "You'll need to scan the QR with WhatsApp → Linked Devices"
    else
        info "WhatsApp skipped"
    fi
}

# ─── Agent Roster ──────────────────────────────────────────────────────────

detect_agents() {
    if detect_env; then
        grep -q "^AGENTS=.\+" "$ENV_FILE" 2>/dev/null
    else
        return 1
    fi
}

setup_agents() {
    step "Agent Roster"

    if detect_agents; then
        local current
        current=$(grep "^AGENTS=" "$ENV_FILE" | cut -d= -f2-)
        ok "Agents already configured: $current"
        echo -n "Reconfigure? (y/N): "
        read -r yn
        if [[ ! "$yn" =~ ^[Yy] ]]; then
            return 0
        fi
    fi

    echo "These are the AI agents CarClaw can address by voice."
    echo "Enter their names separated by commas."
    echo ""
    echo -e "  Default: ${BOLD}Mini, M5, DGX, Copilot${NC}"
    echo ""
    echo -n "Agent names (or Enter for default): "
    read -r agent_input

    if [[ -z "$agent_input" ]]; then
        agent_input="Mini, M5, DGX, Copilot"
    fi

    # Convert "Mini, M5, DGX" → "mini:Mini,m5:M5,dgx:DGX"
    local agents_env=""
    IFS=',' read -ra names <<< "$agent_input"
    for name in "${names[@]}"; do
        name=$(echo "$name" | xargs)  # trim whitespace
        if [[ -n "$name" ]]; then
            local id
            id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            if [[ -n "$agents_env" ]]; then
                agents_env="${agents_env},"
            fi
            agents_env="${agents_env}${id}:${name}"
        fi
    done

    set_env "AGENTS" "$agents_env"
    ok "Agents configured: $agents_env"
}

# ─── .env Management ────────────────────────────────────────────────────────

init_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$BRIDGE_DIR/.env.example" ]]; then
            cp "$BRIDGE_DIR/.env.example" "$ENV_FILE"
            ok "Created .env from template"
        else
            touch "$ENV_FILE"
            ok "Created empty .env"
        fi
    fi
}

set_env() {
    local key="$1" value="$2"

    init_env

    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing value
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        fi
    else
        # Append new key
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# ─── Health Check ────────────────────────────────────────────────────────────

health_check() {
    step "Health Check"

    # Check if bridge can start (quick syntax test)
    info "Checking server.js..."
    if (cd "$BRIDGE_DIR" && node -c server.js 2>/dev/null); then
        ok "server.js syntax valid"
    else
        fail "server.js has syntax errors"
        return 1
    fi

    # Check if port is available
    if has_command lsof; then
        if lsof -i :3100 &>/dev/null; then
            warn "Port 3100 is already in use (bridge may already be running)"
        else
            ok "Port 3100 is available"
        fi
    fi

    ok "Health check passed"
}

# ─── Summary ─────────────────────────────────────────────────────────────────

show_summary() {
    step "Setup Complete!"

    echo ""
    echo -e "${GREEN}CarClaw Bridge is ready.${NC}"
    echo ""
    echo "  Bridge location: $BRIDGE_DIR"
    echo ""

    if [[ -n "${SERVICE_NAME:-}" ]]; then
        echo "  Start:   ${BOLD}${START_CMD:-}${NC}"
        echo "  Stop:    ${BOLD}${STOP_CMD:-}${NC}"
        echo "  Status:  ${BOLD}${STATUS_CMD:-}${NC}"
        echo "  Logs:    ${BOLD}${LOGS_CMD:-}${NC}"
    else
        echo "  Manual start: ${BOLD}cd $BRIDGE_DIR && npm start${NC}"
    fi

    echo ""
    echo -e "  ${DIM}CarClaw app will auto-discover this bridge on your local network.${NC}"
    echo ""
}
