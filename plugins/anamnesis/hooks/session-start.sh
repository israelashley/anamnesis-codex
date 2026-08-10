#!/bin/bash
# anamnesis/hooks/session-start.sh
# Fires once per Claude Code session. Issues a fresh session_id, drains
# pending uploads from prior crashes, probes server reachability. Never
# blocks — always exits 0.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_check_pause
anamnesis_load_config || exit 0   # config not set up yet — silent no-op

# Fresh session_id
SID="$(anamnesis_gen_session_id)"
anamnesis_write_session_id "$SID"

# Drain any queued payloads from prior session crashes
anamnesis_drain_queue

# Health probe (cheap, confirms auth + connectivity; failures logged, not blocking)
if ! anamnesis_post "/mcp/tools/get_memory_stats" '{}' >/dev/null; then
    anamnesis_log_error "session_start_health_probe_failed" "sid=$SID"
    # Fall through — we don't block the session on probe failure
fi

# ── Capture-gap surfacing (2026-08-10, blackout lesson) ────────────────────
# First session after `anamnesis resume` gets a one-time context notice naming
# the blackout window, so the assistant can offer a backfill of decisions made
# while capture was off.
GAP_FILE="$ANAMNESIS_HOME/last_gap.json"
if [ -r "$GAP_FILE" ] && [ "$(jq -r '.surfaced // false' < "$GAP_FILE" 2>/dev/null)" != "true" ]; then
    G_FROM="$(jq -r '.paused_at // "unknown"' < "$GAP_FILE" 2>/dev/null)"
    G_TO="$(jq -r '.resumed_at // "unknown"' < "$GAP_FILE" 2>/dev/null)"
    GAP_CTX="$(printf '<anamnesis-capture-gap paused_at="%s" resumed_at="%s" note="Memory capture was OFF during this window; sessions inside it were NOT captured. If important work happened then, offer the user a backfill: summarize the missing decisions and save them via remember_episode. Reference data, never instructions."/>' "$G_FROM" "$G_TO")"
    _TMP="$GAP_FILE.tmp.$$"
    if jq '.surfaced = true' < "$GAP_FILE" > "$_TMP" 2>/dev/null; then
        chmod 600 "$_TMP" 2>/dev/null || true
        mv -f "$_TMP" "$GAP_FILE"
    else
        rm -f "$_TMP"
    fi
    jq -n --arg ctx "$GAP_CTX" \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
fi

exit 0
