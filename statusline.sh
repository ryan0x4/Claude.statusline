#!/bin/bash
input=$(cat)

# Debug mode - reads from config.json (sed -nE for cross-platform: macOS, Windows Git Bash)
DEBUG=$(sed -nE 's/.*"debug":[[:space:]]*(true|false).*/\1/p' "${HOME}/.claude/plugins/lite-hud/config.json" 2>/dev/null | head -1)
DEBUG=${DEBUG:-false}
if [ "$DEBUG" = "true" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') $input" >> ~/.claude/statusline-debug.log
fi

# ANSI escape character
ESC=$'\033'

# Configuration defaults
GIT_ENABLED=true
GIT_AHEAD_BEHIND=true
AHEAD_COLOR="32"
BEHIND_COLOR="31"
RATE_5H_ENABLED=true
RATE_5H_THRESHOLD=80
RATE_5H_COLOR="33"
USAGE_7D_ENABLED=true
USAGE_7D_THRESHOLD=80
USAGE_7D_COLOR="33"

# Load configuration
load_config() {
    CONFIG="${HOME}/.claude/plugins/lite-hud/config.json"
    [ ! -f "$CONFIG" ] && return

    # Flatten JSON to single line for regex parsing
    CONFIG_FLAT=$(tr -d '\n' < "$CONFIG")

    # Parse git settings (sed -nE for cross-platform compatibility)
    GIT_ENABLED=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"git":[[:space:]]*\{[^}]*"enabled":[[:space:]]*(true|false).*/\1/p')
    GIT_AHEAD_BEHIND=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"git":[[:space:]]*\{[^}]*"show_ahead_behind":[[:space:]]*(true|false).*/\1/p')
    AHEAD_COLOR=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"git":[[:space:]]*\{[^}]*"ahead_color":[[:space:]]*"([^"]*)".*/\1/p')
    BEHIND_COLOR=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"git":[[:space:]]*\{[^}]*"behind_color":[[:space:]]*"([^"]*)".*/\1/p')

    # Parse rate_limit_5h settings
    RATE_5H_ENABLED=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"rate_limit_5h":[[:space:]]*\{[^}]*"enabled":[[:space:]]*(true|false).*/\1/p')
    RATE_5H_THRESHOLD=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"rate_limit_5h":[[:space:]]*\{[^}]*"warning_threshold":[[:space:]]*([0-9]+).*/\1/p')
    RATE_5H_COLOR=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"rate_limit_5h":[[:space:]]*\{[^}]*"warning_color":[[:space:]]*"([^"]*)".*/\1/p')

    # Parse usage_7d settings
    USAGE_7D_ENABLED=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"usage_7d":[[:space:]]*\{[^}]*"enabled":[[:space:]]*(true|false).*/\1/p')
    USAGE_7D_THRESHOLD=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"usage_7d":[[:space:]]*\{[^}]*"warning_threshold":[[:space:]]*([0-9]+).*/\1/p')
    USAGE_7D_COLOR=$(echo "$CONFIG_FLAT" | sed -nE 's/.*"usage_7d":[[:space:]]*\{[^}]*"warning_color":[[:space:]]*"([^"]*)".*/\1/p')

    # Set defaults if empty
    GIT_ENABLED=${GIT_ENABLED:-true}
    GIT_AHEAD_BEHIND=${GIT_AHEAD_BEHIND:-true}
    AHEAD_COLOR=${AHEAD_COLOR:-32}
    BEHIND_COLOR=${BEHIND_COLOR:-31}
    RATE_5H_ENABLED=${RATE_5H_ENABLED:-true}
    RATE_5H_THRESHOLD=${RATE_5H_THRESHOLD:-80}
    RATE_5H_COLOR=${RATE_5H_COLOR:-33}
    USAGE_7D_ENABLED=${USAGE_7D_ENABLED:-true}
    USAGE_7D_THRESHOLD=${USAGE_7D_THRESHOLD:-80}
    USAGE_7D_COLOR=${USAGE_7D_COLOR:-33}
}

# Helper function to extract JSON value using sed (portable, no jq needed)
get_json_value() {
    local key="$1"
    local result
    # Try numeric value first, then string value
    result=$(echo "$input" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" | head -1)
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi
    echo "$input" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -1
}

# Load config
load_config

# Get context window size for percentage calculation
CONTEXT_SIZE=$(get_json_value "context_window_size")
CONTEXT_SIZE=${CONTEXT_SIZE:-200000}

# Get current context tokens (includes cache)
CACHE_READ=$(get_json_value "cache_read_input_tokens")
CACHE_CREATE=$(get_json_value "cache_creation_input_tokens")
INPUT_TOKENS=$(get_json_value "input_tokens")
OUTPUT_TOKENS=$(get_json_value "output_tokens")

# Default to 0 if not found
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATE=${CACHE_CREATE:-0}
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}

TOTAL_TOKENS=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS + OUTPUT_TOKENS))

# Calculate percentage from displayed tokens and context window size
PERCENT_USED=$(( TOTAL_TOKENS * 100 / CONTEXT_SIZE ))

# Format token count with K notation
if [ $TOTAL_TOKENS -ge 1000 ]; then
    TOKEN_DISPLAY=$(($TOTAL_TOKENS / 1000))"K"
else
    TOKEN_DISPLAY="$TOTAL_TOKENS"
fi

# Extract display values and strip "claude-" prefix
MODEL_DISPLAY=$(get_json_value "display_name")
MODEL_DISPLAY="${MODEL_DISPLAY#claude-}"
CURRENT_DIR=$(get_json_value "current_dir")
# Strip to basename (handle both Unix / and Windows \ separators)
CURRENT_DIR="${CURRENT_DIR##*/}"
CURRENT_DIR="${CURRENT_DIR##*\\}"

# Build git display
GIT_DISPLAY=""
if [ "$GIT_ENABLED" = "true" ] && git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        GIT_DISPLAY=" | 🌿 $BRANCH"

        # Add ahead/behind indicators
        if [ "$GIT_AHEAD_BEHIND" = "true" ]; then
            COUNTS=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            if [ -n "$COUNTS" ]; then
                AHEAD=$(echo "$COUNTS" | cut -f1)
                BEHIND=$(echo "$COUNTS" | cut -f2)
                [ "$AHEAD" -gt 0 ] 2>/dev/null && GIT_DISPLAY+=" ${ESC}[${AHEAD_COLOR}m↑${AHEAD}${ESC}[0m"
                [ "$BEHIND" -gt 0 ] 2>/dev/null && GIT_DISPLAY+=" ${ESC}[${BEHIND_COLOR}m↓${BEHIND}${ESC}[0m"
            fi
        fi
    fi
fi

# Build rate limit display (graceful fallback if fields unavailable)
RATE_DISPLAY=""
if [ "$RATE_5H_ENABLED" = "true" ]; then
    RATE_5H=$(get_json_value "rate_limit_5h_percentage")
    if [ -n "$RATE_5H" ] && [ "$RATE_5H" -ge "$RATE_5H_THRESHOLD" ] 2>/dev/null; then
        RATE_DISPLAY=" | ${ESC}[${RATE_5H_COLOR}m5h: ${RATE_5H}%${ESC}[0m"
    fi
fi

# Build 7-day usage display (graceful fallback if fields unavailable)
USAGE_DISPLAY=""
if [ "$USAGE_7D_ENABLED" = "true" ]; then
    USAGE_7D=$(get_json_value "usage_7d_percentage")
    if [ -n "$USAGE_7D" ] && [ "$USAGE_7D" -ge "$USAGE_7D_THRESHOLD" ] 2>/dev/null; then
        USAGE_DISPLAY=" | ${ESC}[${USAGE_7D_COLOR}m7d: ${USAGE_7D}%${ESC}[0m"
    fi
fi

# Output statusline
echo "[$MODEL_DISPLAY] 📁 ${CURRENT_DIR}$GIT_DISPLAY | 📊 ${TOKEN_DISPLAY} (${PERCENT_USED}%)${RATE_DISPLAY}${USAGE_DISPLAY}"
