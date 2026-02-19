# CarClaw Full Setup Guide

Complete guide to setting up CarClaw: bridge server, messaging services, agent roster, Apple Developer entitlement, and the iOS app.

## Architecture Overview

```
iPhone (CarClaw app)
  |
  |  WebSocket (ws://bridge.local:3100)
  |  Discovered via Bonjour/mDNS
  v
Bridge Server (Node.js, any machine on your network)
  |
  |--- Telegram Bot API (polling)
  |--- WhatsApp Web (Puppeteer)
  |--- iMessage (BlueBubbles webhooks, macOS only)
  v
Messaging Groups
  |
  AI Agents respond in group chats
```

The bridge runs on one machine (Mac, Linux, or both). The iOS app discovers it automatically on the local network.

---

## Step 1: Choose Your Bridge Host

| Machine | OS | Best for |
|---------|-------|----------|
| Mac Mini / M5 | macOS | All 3 services (including iMessage) |
| DGX / server | Debian/Ubuntu | Telegram + WhatsApp only |

iMessage requires macOS (BlueBubbles needs Messages.app).

---

## Step 2: Run the Installer

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-mac.sh | bash
```

### Debian / Ubuntu

```bash
curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-debian.sh | bash
```

The wizard will walk you through:
1. Installing Node.js
2. Cloning the bridge server
3. Installing npm dependencies
4. Selecting messaging services (Telegram, WhatsApp, iMessage)
5. Configuring each service (tokens, passwords)
6. Naming your agents (default: Mini, M5, DGX, Copilot)
7. Installing a system service (launchd or systemd)
8. Running a health check

---

## Step 3: Configure Messaging Services

### Telegram (recommended -- most reliable)

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts to create a bot
3. Copy the bot token (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
4. **Disable privacy mode**: Send `/setprivacy` to BotFather, select your bot, choose "Disable"
   - This allows the bot to see all messages in group chats (required for relaying)
5. Create a group chat (e.g. "Nusy Agents")
6. Add your bot to the group
7. Send a message in the group -- the bridge will auto-discover it

### WhatsApp (may be blocked by Meta)

1. The installer enables WhatsApp in `.env`
2. Start the bridge -- a QR code appears in the terminal
3. Open WhatsApp on your phone > Settings > Linked Devices > Link a Device
4. Scan the QR code

**Note:** Meta has been blocking new device linking for WhatsApp Web automation. If QR scanning fails, use Telegram instead.

### iMessage (macOS only, via BlueBubbles)

1. Install [BlueBubbles](https://bluebubbles.app) on your Mac (the installer can do this via Homebrew)
2. Open BlueBubbles, complete initial setup
3. Set a server password in BlueBubbles settings
4. Make sure Messages.app is signed into your iCloud account
5. The installer will:
   - Test the connection to BlueBubbles
   - Write the password to `.env`
   - The bridge auto-registers its webhook on startup

---

## Step 4: Configure Agent Roster

The installer prompts for agent names. You can also edit manually:

```bash
# In ~/carclaw-bridge/.env
AGENTS=mini:Mini,m5:M5,dgx:DGX,copilot:Copilot
```

Format: `id:DisplayName` pairs, comma-separated. The bridge sends this roster to the iOS app on connect, so the app dynamically learns your agent names for voice routing.

To change agents later, edit `.env` and restart the bridge:

```bash
# macOS
launchctl unload ~/Library/LaunchAgents/com.congruentsys.carclaw-bridge.plist
launchctl load ~/Library/LaunchAgents/com.congruentsys.carclaw-bridge.plist

# Debian/Ubuntu
sudo systemctl restart carclaw-bridge
```

---

## Step 5: Verify the Bridge

### Check service status

```bash
# macOS
launchctl list | grep carclaw
tail -f /tmp/carclaw-bridge.log

# Debian/Ubuntu
systemctl status carclaw-bridge
journalctl -u carclaw-bridge -f
```

### Test WebSocket connection

```bash
# From any machine on the network (install wscat: npm i -g wscat)
wscat -c ws://bridge-hostname:3100
```

You should see a JSON status message with service states and agent roster:

```json
{
  "type": "status",
  "telegram": "connected",
  "whatsapp": "disconnected",
  "imessage": "disconnected",
  "agents": [
    {"id": "mini", "name": "Mini"},
    {"id": "m5", "name": "M5"}
  ]
}
```

### Test Bonjour discovery

```bash
# macOS
dns-sd -B _carclaw._tcp

# Debian/Ubuntu
avahi-browse -r _carclaw._tcp
```

---

## Step 6: Apple Developer Setup (for CarPlay)

CarPlay requires an Apple Developer membership and a CarPlay entitlement.

### 6a. Verify Developer Account

1. Log in at https://developer.apple.com
2. Confirm your membership (Congruent Systems PBC or personal) is active
3. Membership is $99/year -- check expiration

### 6b. Request CarPlay Entitlement

1. Go to https://developer.apple.com/contact/carplay/
2. Select **"Voice-Based Conversational"** category
3. App description: "CarClaw -- voice-based command interface for AI agent fleets via CarPlay"
4. Apple reviews the request (can take days to weeks)

**Important:** Start this early. You can develop and test in the CarPlay Simulator without the entitlement, but you need it for on-device testing and App Store submission.

### 6c. Provisioning Profile

Once the entitlement is granted:
1. Open Xcode > Target > Signing & Capabilities
2. Automatic signing should pick up the new entitlement
3. If not: go to Certificates, Identifiers & Profiles on developer.apple.com and regenerate

---

## Step 7: iOS App Setup

### Build from source

```bash
cd ~/Projects
gh repo clone hankh95/carclaw
cd carclaw
```

Open `CarClaw/CarClaw.xcodeproj` in Xcode and build for your iPhone or the simulator.

### CarPlay Simulator Testing

1. Build and run on the iPhone Simulator
2. In Simulator menu: I/O > External Displays > CarPlay
3. A CarPlay window appears alongside the iPhone simulator
4. The app auto-launches into voice mode on CarPlay

### Connect to Your Bridge

In the iOS app:
1. Go to Settings > Bridges
2. Tap "Scan" -- the app discovers bridges via Bonjour
3. Select your bridge
4. Choose a messaging group (e.g. your Telegram group)
5. The app is ready -- speak an agent name to route:
   - "Mini, what is the paper status?"
   - "M5, check the build"
   - "Everyone, status report"

---

## Troubleshooting

### Bridge won't start
- Check logs: `tail -f /tmp/carclaw-bridge.log` (macOS) or `journalctl -u carclaw-bridge -f` (Debian)
- Verify Node.js v18+: `node --version`
- Check `.env` file exists: `cat ~/carclaw-bridge/.env`

### Telegram bot not receiving messages
- Verify privacy mode is disabled: message @BotFather, send `/setprivacy`, select your bot
- Make sure the bot is a member of the group
- Send a message in the group -- the bot should log it

### iOS app can't find the bridge
- Both devices must be on the same local network
- Check Bonjour: `dns-sd -B _carclaw._tcp`
- Try manual connection: enter `ws://hostname:3100` in Settings

### WhatsApp QR code not working
- Meta blocks new device linking for automation libraries
- Use Telegram instead -- it's more reliable for this use case

### iMessage not connecting
- Verify BlueBubbles is running and Messages.app is signed in
- Test BlueBubbles URL: `curl http://localhost:1234/api/v1/server/info?password=YOUR_PASSWORD`
- Check bridge logs for webhook registration

---

## Environment Reference

All configuration lives in `~/carclaw-bridge/.env`:

| Variable | Description | Default |
|----------|-------------|---------|
| `WS_PORT` | WebSocket port | 3100 |
| `TELEGRAM_TOKEN` | Bot token from @BotFather | -- |
| `WHATSAPP_ENABLED` | Enable WhatsApp | false |
| `IMESSAGE_ENABLED` | Enable iMessage | false |
| `BLUEBUBBLES_URL` | BlueBubbles server URL | http://localhost:1234 |
| `BLUEBUBBLES_PASSWORD` | BlueBubbles password | -- |
| `WEBHOOK_PORT` | HTTP port for BlueBubbles webhooks | 3101 |
| `AGENTS` | Agent roster (id:Name pairs) | mini:Mini,m5:M5,dgx:DGX,copilot:Copilot |
| `SESSION_DIR` | WhatsApp session storage | ./.wwebjs_auth |

---

Congruent Systems PBC
