#!/bin/bash

# Fast-path: CLI setup helpers
if [ "$1" = "--setup-agy" ] || [ "$1" = "--setup-antigravity" ]; then
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    CONFIG_DIR="${HOME:-$USERPROFILE}/.gemini/antigravity-cli"
    SETTINGS_FILE="${CONFIG_DIR}/settings.json"
    mkdir -p "$CONFIG_DIR"

    # Detect if running under Windows (MSYS/Git Bash/Cygwin/native Windows)
    IS_WINDOWS=false
    case "$OSTYPE" in
        msys*|cygwin*|win32*) IS_WINDOWS=true ;;
    esac
    if [ -n "$WINDIR" ] || [ -n "$SYSTEMROOT" ]; then
        IS_WINDOWS=true
    fi

    CMD_SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.cmd"
    if [ "$IS_WINDOWS" = "true" ] && [ -f "$CMD_SCRIPT" ]; then
        if command -v cygpath >/dev/null 2>&1; then
            TARGET_CMD="$(cygpath -w "$CMD_SCRIPT")"
        else
            TARGET_CMD="$CMD_SCRIPT"
        fi
    else
        TARGET_CMD="$SCRIPT_PATH"
    fi

    if [ -f "$SETTINGS_FILE" ]; then
        python3 -c "
import json
p = '$SETTINGS_FILE'
try:
    with open(p, 'r') as f:
        d = json.load(f)
    d['statusLine'] = {'type': 'command', 'command': '$TARGET_CMD'}
    with open(p, 'w') as f:
        json.dump(d, f, indent=2)
    print('✓ Updated statusLine in $SETTINGS_FILE')
except Exception as e:
    print('Error:', e)
" 2>/dev/null || {
            echo "Failed to auto-update settings.json. Please run in Antigravity chat:"
            echo "/statusline $TARGET_CMD"
            exit 1
        }
    else
        cat << EOF > "$SETTINGS_FILE"
{
  "statusLine": {
    "type": "command",
    "command": "$TARGET_CMD"
  }
}
EOF
        echo "✓ Created $SETTINGS_FILE with statusLine configuration"
    fi
    echo "✓ lite-hud statusline configured for Antigravity CLI ($TARGET_CMD)"
    exit 0
fi

# Strip Windows carriage returns (\r) immediately to avoid arithmetic & syntax errors
input=$(cat | tr -d '\r')

ESC=$'\033'
USER_HOME="${HOME:-$USERPROFILE}"
CONFIG_FILE="${USER_HOME}/.claude/plugins/lite-hud/config.json"
CACHE_FILE="${USER_HOME}/.claude/plugins/lite-hud/config.cache.sh"
if [ ! -f "$CONFIG_FILE" ] && [ -f "${USER_HOME}/.config/lite-hud/config.json" ]; then
    CONFIG_FILE="${USER_HOME}/.config/lite-hud/config.json"
    CACHE_FILE="${USER_HOME}/.config/lite-hud/config.cache.sh"
fi

# Configuration defaults
GIT_ENABLED=true
GIT_AHEAD_BEHIND=true
AHEAD_COLOR=32
BEHIND_COLOR=31
RATE_5H_ENABLED=true
RATE_5H_THRESHOLD=80
RATE_5H_COLOR=33
USAGE_7D_ENABLED=true
USAGE_7D_THRESHOLD=80
USAGE_7D_COLOR=33
DEBUG=false

# Shared awk library: POSIX-only, no gawk extensions. Works on BSD awk (macOS),
# mawk, and gawk alike. Uses match()+substr() for pseudo-capture semantics;
# get_object() walks braces so it handles nested objects of arbitrary depth
# (replaces the upstream bash regex that only covered one level of nesting).
AWK_LIB='
function find_value(s, re,   v) {
    if (!match(s, re)) return ""
    v = substr(s, RSTART, RLENGTH)
    sub(/^"[^"]+"[[:space:]]*:[[:space:]]*/, "", v)
    gsub(/\r/, "", v)
    return v
}
function bool_val(s, key)  { return find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*(true|false)") }
function num_val(s, key)   { return find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+") }
function float_val(s, key) { return find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*[0-9.]+") }
function str_val(s, key,   v) {
    v = find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")
    if (v == "") return ""
    return substr(v, 2, length(v) - 2)
}
function get_object(s, key,   i, start, depth, ch) {
    if (!match(s, "\"" key "\"[[:space:]]*:[[:space:]]*\\{")) return ""
    start = RSTART + RLENGTH - 1
    i = start + 1
    depth = 1
    while (i <= length(s) && depth > 0) {
        ch = substr(s, i, 1)
        if (ch == "{") depth++
        else if (ch == "}") depth--
        i++
    }
    if (depth == 0) return substr(s, start, i - start)
    return ""
}
function emit(var, val)      { if (val != "") print var "=\"" val "\"" }
function emit_num(var, val)  { if (val != "") print var "=" val }
# Output is passed to eval: escape every char special inside double quotes.
function emit_str(var, val,   v) {
    if (val == "") return
    v = val
    gsub(/[\\"$`]/, "\\\\&", v)
    print var "=\"" v "\""
}
'

# Load config via cache: the awk pass runs only when config.json is newer than
# the cache snippet, so the common-case hot path does zero JSON work.
if [ -f "$CONFIG_FILE" ]; then
    if [ ! -f "$CACHE_FILE" ] || [ "$CONFIG_FILE" -nt "$CACHE_FILE" ]; then
        CACHE_DIR="$(dirname "$CACHE_FILE")"
        if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
            awk "BEGIN { RS = \"\" } $AWK_LIB"'
            {
                emit("DEBUG", bool_val($0, "debug"))
                g = get_object($0, "git")
                if (g != "") {
                    emit("GIT_ENABLED", bool_val(g, "enabled"))
                    emit("GIT_AHEAD_BEHIND", bool_val(g, "show_ahead_behind"))
                    emit("AHEAD_COLOR", str_val(g, "ahead_color"))
                    emit("BEHIND_COLOR", str_val(g, "behind_color"))
                }
                r = get_object($0, "rate_limit_5h")
                if (r != "") {
                    emit("RATE_5H_ENABLED", bool_val(r, "enabled"))
                    emit("RATE_5H_THRESHOLD", num_val(r, "warning_threshold"))
                    emit("RATE_5H_COLOR", str_val(r, "warning_color"))
                }
                u = get_object($0, "usage_7d")
                if (u != "") {
                    emit("USAGE_7D_ENABLED", bool_val(u, "enabled"))
                    emit("USAGE_7D_THRESHOLD", num_val(u, "warning_threshold"))
                    emit("USAGE_7D_COLOR", str_val(u, "warning_color"))
                }
            }' "$CONFIG_FILE" > "$CACHE_FILE" 2>/dev/null
            [ -f "$CACHE_FILE" ] && . "$CACHE_FILE"
        fi
    else
        . "$CACHE_FILE"
    fi
fi

[ "$DEBUG" = "true" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $input" >> "${USER_HOME}/.claude/statusline-debug.log"

# Parse stdin in a single awk pass.
eval "$(printf '%s' "$input" | awk "BEGIN { RS = \"\" } $AWK_LIB"'
    {
        ctx = get_object($0, "context_window")
        scope = (ctx != "") ? ctx : $0
        emit_num("CONTEXT_SIZE", num_val(scope, "context_window_size"))
        emit_num("CACHE_READ", num_val(scope, "cache_read_input_tokens"))
        emit_num("CACHE_CREATE", num_val(scope, "cache_creation_input_tokens"))
        emit_num("INPUT_TOKENS", num_val(scope, "input_tokens"))
        emit_num("OUTPUT_TOKENS", num_val(scope, "output_tokens"))
        emit_num("TOTAL_INPUT_TOKENS", num_val(scope, "total_input_tokens"))
        if (ctx != "") {
            pct = float_val(ctx, "used_percentage")
            if (pct != "") emit_num("PERCENT_USED_PREROUNDED", int(pct + 0.5))
        }
        rl = get_object($0, "rate_limits")
        if (rl != "") {
            emit_num("RATE_5H", num_val(get_object(rl, "five_hour"), "used_percentage"))
            emit_num("USAGE_7D", num_val(get_object(rl, "seven_day"), "used_percentage"))
        }
        quota = get_object($0, "quota")
        if (quota != "") {
            g5 = get_object(quota, "gemini-5h")
            if (g5 == "") g5 = get_object(quota, "3p-5h")
            if (g5 != "") {
                rf = float_val(g5, "remaining_fraction")
                if (rf != "") emit_num("RATE_5H", int((1.0 - rf) * 100 + 0.5))
            }
            gw = get_object(quota, "gemini-weekly")
            if (gw == "") gw = get_object(quota, "3p-weekly")
            if (gw != "") {
                rf = float_val(gw, "remaining_fraction")
                if (rf != "") emit_num("USAGE_7D", int((1.0 - rf) * 100 + 0.5))
            }
        }
        m = str_val($0, "display_name")
        if (m == "") {
            mobj = get_object($0, "model")
            if (mobj != "") m = str_val(mobj, "display_name")
            if (m == "") m = str_val(mobj, "model")
        }
        emit_str("MODEL_DISPLAY", m)

        cd = str_val($0, "current_dir")
        if (cd == "") {
            ws = get_object($0, "workspace")
            if (ws != "") cd = str_val(ws, "current_dir")
        }
        if (cd == "") cd = str_val($0, "cwd")
        emit_str("CURRENT_DIR", cd)
    }
')"

CONTEXT_SIZE=${CONTEXT_SIZE:-200000}
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATE=${CACHE_CREATE:-0}
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}

# Prefer Antigravity cumulative context tokens, falling back to Claude turn sum
if [ -n "$TOTAL_INPUT_TOKENS" ] && [ "$TOTAL_INPUT_TOKENS" -gt 0 ] 2>/dev/null; then
    TOTAL_TOKENS="$TOTAL_INPUT_TOKENS"
else
    TOTAL_TOKENS=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS + OUTPUT_TOKENS))
fi

# Prefer pre-rounded used_percentage, falling back to manual calc
if [ -n "$PERCENT_USED_PREROUNDED" ]; then
    PERCENT_USED="$PERCENT_USED_PREROUNDED"
elif [ "$CONTEXT_SIZE" -gt 0 ]; then
    PERCENT_USED=$(( TOTAL_TOKENS * 100 / CONTEXT_SIZE ))
else
    PERCENT_USED=0
fi

# Format token counts (e.g. 15K, 34K, 1.2M)
if [ "$TOTAL_TOKENS" -ge 1000000 ]; then
    T_M=$((TOTAL_TOKENS / 1000000))
    T_REM=$(( (TOTAL_TOKENS % 1000000) / 100000 ))
    if [ "$T_REM" -gt 0 ]; then
        TOKEN_DISPLAY="${T_M}.${T_REM}M"
    else
        TOKEN_DISPLAY="${T_M}M"
    fi
elif [ "$TOTAL_TOKENS" -ge 1000 ]; then
    TOKEN_DISPLAY="$((TOTAL_TOKENS / 1000))K"
else
    TOKEN_DISPLAY="$TOTAL_TOKENS"
fi

MODEL_DISPLAY="${MODEL_DISPLAY#claude-}"
MODEL_DISPLAY="${MODEL_DISPLAY#google-}"
MODEL_DISPLAY="${MODEL_DISPLAY% (High)}"
MODEL_DISPLAY="${MODEL_DISPLAY:-AI}"

FULL_DIR="${CURRENT_DIR:-$PWD}"
CURRENT_DIR="${FULL_DIR##*/}"
CURRENT_DIR="${CURRENT_DIR##*\\}"

GIT_DISPLAY=""
if [ "$GIT_ENABLED" = "true" ]; then
    target_dir="$FULL_DIR"
    if [ -d "$target_dir" ] && git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BRANCH=$(git -C "$target_dir" branch --show-current 2>/dev/null | tr -d '\r')
        [ -z "$BRANCH" ] && BRANCH=$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null | tr -d '\r')
        if [ -n "$BRANCH" ]; then
            GIT_DISPLAY=" | 🌿 $BRANCH"
            if [ "$GIT_AHEAD_BEHIND" = "true" ]; then
                COUNTS=$(git -C "$target_dir" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null | tr -d '\r')
                if [ -n "$COUNTS" ]; then
                    AHEAD="${COUNTS%%[[:space:]]*}"
                    BEHIND="${COUNTS##*[[:space:]]}"
                    [ "$AHEAD" -gt 0 ] 2>/dev/null && GIT_DISPLAY+=" ${ESC}[${AHEAD_COLOR}m↑${AHEAD}${ESC}[0m"
                    [ "$BEHIND" -gt 0 ] 2>/dev/null && GIT_DISPLAY+=" ${ESC}[${BEHIND_COLOR}m↓${BEHIND}${ESC}[0m"
                fi
            fi
        fi
    fi
fi

RATE_DISPLAY=""
if [ "$RATE_5H_ENABLED" = "true" ] && [ -n "$RATE_5H" ] && [ "$RATE_5H" -ge "$RATE_5H_THRESHOLD" ] 2>/dev/null; then
    RATE_DISPLAY=" | ${ESC}[${RATE_5H_COLOR}m5h: ${RATE_5H}%${ESC}[0m"
fi

USAGE_DISPLAY=""
if [ "$USAGE_7D_ENABLED" = "true" ] && [ -n "$USAGE_7D" ] && [ "$USAGE_7D" -ge "$USAGE_7D_THRESHOLD" ] 2>/dev/null; then
    USAGE_DISPLAY=" | ${ESC}[${USAGE_7D_COLOR}m7d: ${USAGE_7D}%${ESC}[0m"
fi

echo "[$MODEL_DISPLAY] 📁 ${CURRENT_DIR}$GIT_DISPLAY | 📊 ${TOKEN_DISPLAY} (${PERCENT_USED}%)${RATE_DISPLAY}${USAGE_DISPLAY}"
