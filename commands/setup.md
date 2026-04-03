---
description: Configure Claude Code statusLine to use lite-hud plugin
---

# Setup lite-hud statusline

Configure Claude Code to use the lite-hud statusline script.

## Task

1. Find the plugin root using `CLAUDE_PLUGIN_ROOT` environment variable
2. Copy `config.json` to `~/.claude/plugins/lite-hud/` (only if not exists, to preserve user customizations)
3. Configure `statusLine` in `~/.claude/settings.json` to point to the plugin's `statusline.sh`

## Instructions

Execute these steps directly:

### Step 1: Locate plugin and verify
```bash
# CLAUDE_PLUGIN_ROOT points to this plugin's installed directory
ls "$CLAUDE_PLUGIN_ROOT/statusline.sh"
```

### Step 2: Create user config directory and copy default config (preserve existing)
```bash
mkdir -p ~/.claude/plugins/lite-hud
[ ! -f ~/.claude/plugins/lite-hud/config.json ] && \
  cp "$CLAUDE_PLUGIN_ROOT/config.json" ~/.claude/plugins/lite-hud/
```

### Step 3: Configure statusLine in settings.json
Set statusLine to: `$CLAUDE_PLUGIN_ROOT/statusline.sh`

Read `~/.claude/settings.json`, add or update the `statusLine` key with the resolved absolute path from `CLAUDE_PLUGIN_ROOT`, and write back.

## After Setup

Inform the user to restart Claude Code after setup.
