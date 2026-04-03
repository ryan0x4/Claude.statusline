---
description: Configure Claude Code statusLine to use lite-hud plugin
---

# Setup lite-hud statusline

Configure Claude Code to use the lite-hud statusline script.

## Instructions

### Step 1: Find the plugin
Find `statusline.sh` under `~/.claude/plugins/marketplaces/` using glob search. Store the resolved absolute path as `PLUGIN_DIR` for subsequent steps. If not found, tell the user the plugin is not installed.

### Step 2: Copy default config (preserve existing)
```bash
mkdir -p ~/.claude/plugins/lite-hud
[ ! -f ~/.claude/plugins/lite-hud/config.json ] && \
  cp "$PLUGIN_DIR/config.json" ~/.claude/plugins/lite-hud/
```

### Step 3: Configure statusLine in settings.json
Read `~/.claude/settings.json`, add or update the `statusLine` key with the path found in Step 1:
```json
{
  "statusLine": {
    "type": "command",
    "command": "<PLUGIN_DIR>/statusline.sh"
  }
}
```
Use `~` prefix (not absolute `/home/...`) for portability.

### Done
Tell the user to restart Claude Code.
