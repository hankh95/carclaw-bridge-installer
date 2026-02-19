# CarClaw Bridge Installer

Open-source installers for setting up the [CarClaw](https://github.com/hankh95/carclaw) bridge server on macOS and Debian/Ubuntu.

The bridge connects your messaging services (Telegram, WhatsApp, iMessage) to the CarClaw iOS app via WebSocket, enabling voice control of your AI agent fleet from your car.

## Quick Install

### macOS (M5, Mac Mini, MacBook)

```bash
curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-mac.sh | bash
```

### Debian / Ubuntu (DGX, servers)

```bash
curl -fsSL https://raw.githubusercontent.com/hankh95/carclaw-bridge-installer/main/install-debian.sh | bash
```

## What It Does

The installer wizard:

1. **Detects current state** -- skips steps you've already completed
2. **Installs Node.js** -- via Homebrew (Mac) or NodeSource (Debian)
3. **Clones the bridge** -- downloads carclaw-bridge from GitHub
4. **Installs dependencies** -- `npm install`
5. **Asks which services** -- multi-select from available options:

   | Service | macOS | Debian |
   |---------|:-----:|:------:|
   | Telegram | Y | Y |
   | WhatsApp | Y | Y |
   | iMessage | Y | -- |

6. **Configures each service** -- tokens, passwords, QR codes
7. **Installs system service** -- launchd (Mac) or systemd (Debian)
8. **Runs health check** -- verifies everything works
9. **Starts the bridge** -- ready for CarClaw to discover

## Service Details

### Telegram
- Requires a bot token from [@BotFather](https://t.me/BotFather)
- The installer validates the token via API
- Don't forget to disable privacy mode (`/setprivacy` in BotFather)

### WhatsApp
- Uses WhatsApp Web (Puppeteer)
- QR code appears in terminal on first run
- Note: Meta may block new device linking

### iMessage (macOS only)
- Uses [BlueBubbles](https://bluebubbles.app) as the backend
- Requires Messages.app signed into iCloud
- The installer can install BlueBubbles via Homebrew

## Uninstall

```bash
./install-mac.sh --uninstall
# or
./install-debian.sh --uninstall
```

## Re-running

The installer is safe to re-run. It detects what's already installed and skips completed steps. Use it to add new services or fix configuration.

## License

ISC -- Congruent Systems PBC
