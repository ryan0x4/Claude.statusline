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

# Helper function to extract JSON value using sed (portable, no jq needed).
# Pass an optional $2 to restrict the search to a substring (e.g. a scoped
# parent object), avoiding collisions when the same key appears in sibling
# objects elsewhere in the JSON.
get_json_value() {
    local key="$1"
    local scope="${2:-$input}"
    local result
    # Try numeric value first; fall through to string value if numeric is empty.
    result=$(echo "$scope" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" | head -1)
    if [ -z "$result" ]; then
        result=$(echo "$scope" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -1)
    fi
    echo "$result"
}

# Extract the "context_window" object so downstream lookups can scope to it
# and avoid the flat-search collision bug (where e.g. rate_limits.*.used_percentage
# would match first due to greedy regex). The pattern below assumes context_window
# contains at most one nested object (current_usage) — matches Claude Code's
# v2.1.94 schema. If the shape changes and the match fails, CTX_WINDOW stays
# empty; downstream code handles that explicitly — SCOPE falls back below for
# token lookups, and the percentage selection falls through to manual calc.
CTX_WINDOW=""
if [[ "$input" =~ \"context_window\"[[:space:]]*:[[:space:]]*(\{[^{}]*(\{[^{}]*\})?[^{}]*\}) ]]; then
    CTX_WINDOW="${BASH_REMATCH[1]}"
fi
# Best-effort scope for non-colliding token field lookups: prefer the extracted
# context_window, but fall back to whole $input if extraction failed. Safe only
# because the token field names (cache_read_input_tokens, etc.) are unique in
# the current schema — do NOT use this for used_percentage (see below).
SCOPE="${CTX_WINDOW:-$input}"

# Load config
load_config

# Get context window size for percentage calculation (scoped lookup)
CONTEXT_SIZE=$(get_json_value "context_window_size" "$SCOPE")
CONTEXT_SIZE=${CONTEXT_SIZE:-200000}

# Get current context tokens (includes cache) — all scoped to context_window
CACHE_READ=$(get_json_value "cache_read_input_tokens" "$SCOPE")
CACHE_CREATE=$(get_json_value "cache_creation_input_tokens" "$SCOPE")
INPUT_TOKENS=$(get_json_value "input_tokens" "$SCOPE")
OUTPUT_TOKENS=$(get_json_value "output_tokens" "$SCOPE")

# Default to 0 if not found
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATE=${CACHE_CREATE:-0}
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}

TOTAL_TOKENS=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS + OUTPUT_TOKENS))

# Prefer Claude Code's pre-rounded used_percentage (matches /context exactly).
# Only query when CTX_WINDOW extraction succeeded — passing an empty scope to
# get_json_value would let its ${2:-$input} default silently widen the search
# to the whole JSON and re-trigger the rate_limits.*.used_percentage collision.
# Fall back to manual calc during session startup (current_usage: null) or if
# the schema changes and scope extraction stops finding context_window.
PERCENT_USED=""
if [ -n "$CTX_WINDOW" ]; then
    PERCENT_USED=$(get_json_value "used_percentage" "$CTX_WINDOW")
fi
if [ -z "$PERCENT_USED" ]; then
    PERCENT_USED=$(( TOTAL_TOKENS * 100 / CONTEXT_SIZE ))
fi

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
