# lite-hud

Lightweight zero-dependency statusline for Claude Code. Pure bash — no Node.js required.

## Features

- **Model display**: Shows current Claude model (stripped prefix)
- **Directory**: Current working directory basename
- **Git info**: Branch name with ahead/behind indicators (colored)
- **Token usage**: Session tokens with percentage used
- **Rate limits**: 5-hour and 7-day usage warnings (configurable thresholds)
- **Zero dependencies**: Works everywhere Claude Code runs (macOS, Linux, Windows Git Bash)

## Installation

```bash
# Add marketplace
/plugin marketplace add Im-YoungWoo/lite-hud

# Install
/plugin install lite-hud

# Configure statusline
/lite-hud:setup
```

Restart Claude Code after setup.

## Update

```bash
/plugin update lite-hud
/lite-hud:setup
```

## Configuration

Edit `~/.claude/plugins/lite-hud/config.json`:

```json
{
  "debug": false,
  "git": {
    "enabled": true,
    "show_ahead_behind": true,
    "ahead_color": "32",
    "behind_color": "31"
  },
  "rate_limit_5h": {
    "enabled": true,
    "warning_threshold": 0,
    "warning_color": "33"
  },
  "usage_7d": {
    "enabled": true,
    "warning_threshold": 80,
    "warning_color": "33"
  }
}
```

### Color Codes

ANSI color codes: 31=red, 32=green, 33=yellow, 34=blue, 35=magenta, 36=cyan

### Thresholds

- `warning_threshold`: Show warning when usage exceeds this percentage (0 = always show)

## Uninstall

```bash
/plugin uninstall lite-hud
```

Then remove statusLine from `~/.claude/settings.json`.

## License

MIT License
