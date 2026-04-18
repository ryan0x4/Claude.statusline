#!/bin/bash
input=$(cat)

ESC=$'\033'
CONFIG_FILE="${HOME}/.claude/plugins/lite-hud/config.json"
CACHE_FILE="${HOME}/.claude/plugins/lite-hud/config.cache.sh"

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
    return v
}
function bool_val(s, key) { return find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*(true|false)") }
function num_val(s, key)  { return find_value(s, "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+") }
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
function emit_str(var, val,   v) {
    if (val == "") return
    v = val
    gsub(/\\\\/, "\\\\\\\\", v)
    gsub(/"/, "\\\"", v)
    print var "=\"" v "\""
}
'

# Load config via cache: the awk pass runs only when config.json is newer than
# the cache snippet, so the common-case hot path does zero JSON work.
if [ -f "$CONFIG_FILE" ]; then
    if [ ! -f "$CACHE_FILE" ] || [ "$CONFIG_FILE" -nt "$CACHE_FILE" ]; then
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
        }' "$CONFIG_FILE" > "$CACHE_FILE"
    fi
    . "$CACHE_FILE"
fi

[ "$DEBUG" = "true" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $input" >> ~/.claude/statusline-debug.log

# Parse stdin in a single awk pass. Token fields and used_percentage are
# looked up inside the context_window object to avoid the rate_limits.*.
# used_percentage collision (same invariant as the upstream sed version).
# When context_window is missing, token lookups fall back to the whole
# input but PERCENT_USED_PREROUNDED stays empty so we manual-calc below.
eval "$(printf '%s' "$input" | awk "BEGIN { RS = \"\" } $AWK_LIB"'
    {
        ctx = get_object($0, "context_window")
        scope = (ctx != "") ? ctx : $0
        emit_num("CONTEXT_SIZE", num_val(scope, "context_window_size"))
        emit_num("CACHE_READ", num_val(scope, "cache_read_input_tokens"))
        emit_num("CACHE_CREATE", num_val(scope, "cache_creation_input_tokens"))
        emit_num("INPUT_TOKENS", num_val(scope, "input_tokens"))
        emit_num("OUTPUT_TOKENS", num_val(scope, "output_tokens"))
        if (ctx != "") emit_num("PERCENT_USED_PREROUNDED", num_val(ctx, "used_percentage"))
        emit_num("RATE_5H", num_val($0, "rate_limit_5h_percentage"))
        emit_num("USAGE_7D", num_val($0, "usage_7d_percentage"))
        emit_str("MODEL_DISPLAY", str_val($0, "display_name"))
        emit_str("CURRENT_DIR", str_val($0, "current_dir"))
    }
')"

CONTEXT_SIZE=${CONTEXT_SIZE:-200000}
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATE=${CACHE_CREATE:-0}
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}

TOTAL_TOKENS=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS + OUTPUT_TOKENS))

# Prefer Claude Code's pre-rounded used_percentage (matches /context exactly),
# falling back to manual calc during startup (current_usage: null) or when
# the context_window object is absent.
if [ -n "$PERCENT_USED_PREROUNDED" ]; then
    PERCENT_USED="$PERCENT_USED_PREROUNDED"
else
    PERCENT_USED=$(( TOTAL_TOKENS * 100 / CONTEXT_SIZE ))
fi

if [ "$TOTAL_TOKENS" -ge 1000 ]; then
    TOKEN_DISPLAY="$((TOTAL_TOKENS / 1000))K"
else
    TOKEN_DISPLAY="$TOTAL_TOKENS"
fi

MODEL_DISPLAY="${MODEL_DISPLAY#claude-}"
CURRENT_DIR="${CURRENT_DIR##*/}"
CURRENT_DIR="${CURRENT_DIR##*\\}"

GIT_DISPLAY=""
if [ "$GIT_ENABLED" = "true" ]; then
    is_git=""
    dir="$PWD"
    while [ -n "$dir" ]; do
        [ -e "$dir/.git" ] && { is_git=1; break; }
        parent="${dir%/*}"
        [ "$parent" = "$dir" ] && break
        dir="$parent"
    done
    if [ -n "$is_git" ]; then
        BRANCH=$(git branch --show-current 2>/dev/null)
        if [ -n "$BRANCH" ]; then
            GIT_DISPLAY=" | 🌿 $BRANCH"
            if [ "$GIT_AHEAD_BEHIND" = "true" ]; then
                COUNTS=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
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
