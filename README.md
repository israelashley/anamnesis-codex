# anamnesis — persistent encrypted memory for OpenAI Codex CLI

Three lifecycle hooks capture every Codex CLI session. A per-user
HKDF-derived key encrypts content server-side — nobody at smtry.ai can
read it without your credentials. Browse, search, and delete any memory
at [anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory).

Companion to [`anamnesis-claude-code`](https://github.com/israelashley/anamnesis-claude-code)
and [`anamnesis-gemini-cli`](https://github.com/israelashley/anamnesis-gemini-cli).
Same backend, same memory root, same engrams — your work in Codex,
Gemini, and Claude lands in one place.

## Install

```
codex plugin marketplace add israelashley/anamnesis-codex
```

Then, once:

```
~/.codex/plugins/cache/anamnesis@*/bin/anamnesis-config
```

(Or run `anamnesis-config` from any directory if you've installed
the Claude Code plugin or Gemini extension — they bundle the same
helper. `~/.anamnesis/config.json` is shared across all three.)

`anamnesis-config` starts a loopback server, registers a Dynamic Client
(RFC 7591), opens your browser to
`anamnesis.smtry.ai/oauth/authorize`, and catches the redirect. You
paste your api_key on the consent page, approve the scopes
(`memory.read memory.write` by default — add `--allow-delete` to also
request `memory.delete`), and return to the terminal. Access + refresh
tokens land in `~/.anamnesis/config.json` (mode 0600); hooks rotate
the refresh token automatically before expiry.

**If you've already run `anamnesis-config` from a sibling extension,
skip this step.** All three plugins read the same config file.

## Launch — `anamnesis-codex-launch` instead of `codex`

Codex's MCP client expects the OAuth Bearer token in an environment
variable (`ANAMNESIS_ACCESS_TOKEN`) at process start, rather than
running its own OAuth dance. The bundled wrapper handles this:

```
~/.codex/plugins/cache/anamnesis@*/bin/anamnesis-codex-launch
```

Or — recommended — alias it:

```bash
alias codex='~/.codex/plugins/cache/anamnesis@latest/bin/anamnesis-codex-launch'
```

The wrapper:
1. Reads `~/.anamnesis/config.json`
2. Refreshes the access token if it's within 60s of expiry
3. Exports `ANAMNESIS_ACCESS_TOKEN`
4. Execs `codex` with all forwarded args

**The lifecycle hooks work either way** — they read the token directly
from `config.json` via `common.sh`, independent of the env var. The
wrapper exists only so model-invoked MCP tool calls (`retrieve_memories`,
etc.) work inside Codex, not just the deterministic capture path.

## What the hooks do

| Hook | When | What it does |
|------|------|--------------|
| `SessionStart` | Once per session | Issues a fresh `session_id`, drains the pending-upload queue, probes server reachability. |
| `UserPromptSubmit` | Before every user turn | Retrieves top-5 relevant engrams + a **server-time anchor** (authoritative, from the HTTP `Date:` header), injects them as `additionalContext`. |
| `Stop` | After every assistant turn | Captures the prompt + response via `log_session`. Server dedups by SHA-256 prefix — re-sends are idempotent. |

All three are POSIX shell scripts that use `curl` + `jq`. No Node, no
compiled binaries. `python3` is only required once, by
`anamnesis-config`, for the PKCE loopback server during OAuth consent.

## What's missing — `SessionEnd`

Codex CLI **does not expose a `SessionEnd` lifecycle event** as of
v0.124+ (Claude Code does; Gemini does). On those clients we trigger
`/mcp/tools/session_close` immediately when a session ends, advancing
the server-side pipeline (episodes → echoes → engrams) for that
session's content.

In Codex, that pipeline advance falls to the **server's nightly
batch reflection** (per ADR-060 §4 — the 11 PM PT batch that
processes any sessions without an explicit close). Net effect:
your engrams from a Codex session crystallize ~once a day instead
of immediately on session exit. Functional, just slower.

If OpenAI ships a `SessionEnd` event in a future Codex release,
this plugin gains the fourth hook in a follow-up version.

## Control surface

```
anamnesis                  status (default)
anamnesis pause            suspend capture — hooks become no-ops
anamnesis resume           re-enable capture
```

The `paused` sentinel file at `~/.anamnesis/paused` is the first thing
every hook checks. Deleting the file resumes immediately. **Pausing
also pauses the Claude Code plugin and the Gemini extension** — the
sentinel is global to your machine.

## Configuration files

| Path | Contents | Mode |
|------|----------|------|
| `~/.anamnesis/config.json` | OAuth: handle, server_url, access_token, refresh_token, expires_at, client_id. Legacy: api_key, handle, server_url. | 0600 |
| `~/.anamnesis/current_session.json` | session_id for the live session | 0600 |
| `~/.anamnesis/paused` | present ⇒ hooks exit 0 silently | 0600 |
| `~/.anamnesis/pending_uploads/*.json` | queued payloads from prior failures; drained on next SessionStart | 0600 |
| `~/.anamnesis/hook_errors.log` | structured JSONL of transient errors — for debugging only | 0644 |

All state is user-local and user-readable. Nothing in
`~/.codex/config.toml` holds your api_key.

## Failure behavior

Hooks **never block Codex.** On any server error they:

1. Print a one-line warning to stderr.
2. Append a structured entry to `~/.anamnesis/hook_errors.log`.
3. Queue the failed payload under `~/.anamnesis/pending_uploads/`.
4. Exit `1` — non-blocking. Codex continues the session.

The next `SessionStart` drains the queue before doing anything else.

## What's different from the Claude / Gemini versions

The hook lifecycle is mostly the same — `UserPromptSubmit` and `Stop`
match Claude Code's hook names verbatim. Differences:

- **No `SessionEnd`** — see above. Pipeline advance happens via the
  nightly batch instead of immediately on exit.
- **OAuth token must be in an env var for Codex's MCP client** —
  hence the `anamnesis-codex-launch` wrapper. The hooks read the
  token directly from `config.json` and don't need the env var.
- **Token-usage telemetry disabled** — Codex emits OpenAI-shape usage
  which the current `/mcp/tools/track_usage` ingestion path doesn't
  understand. The dashboard's Tokens Paid card stays Claude-Code-only
  until a multi-vendor variant ships.

## Uninstall

```
codex plugin uninstall anamnesis
rm -rf ~/.anamnesis   # optional — removes local config + queued uploads
```

If you also use the Claude Code plugin or Gemini extension, leave
`~/.anamnesis/` alone — it's shared.

Delete your server-side memory at `anamnesis.smtry.ai/memory` if you
want all traces gone. Deletes are cryptographic — content is written
to disk encrypted under your key; when you delete we also drop the key
reference, so recovery is structurally impossible.

## License

MIT. See [`LICENSE`](LICENSE).
