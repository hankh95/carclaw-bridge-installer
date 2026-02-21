# CarClaw Bridge Installer — Claude Code Instructions

Installation scripts for deploying carclaw-bridge on Mac and Debian systems.

## Project Overview

- **Language:** Bash
- **Platform:** macOS, Debian/Ubuntu

## Development Practices

### Branch + PR Pattern (Required)

All implementation work goes through feature branches and pull requests:

1. Create a feature branch: `git checkout -b feat-short-description`
2. Do all implementation work on the branch — **never push directly to main**
3. Test installation scripts on target platform
4. Push and create PR: `gh pr create`
5. Get review from another developer/agent before merging

### Code Quality

- Prefer editing existing files over creating new ones
- Test scripts on both macOS and Debian when possible
- Use `set -e` for error handling in bash scripts
- Don't hardcode paths — use environment variables or auto-detection

## Related Projects

- **carclaw-bridge** — The bridge server these scripts install
- **noesis-ship** — The communication platform
