# OpenCode route — security review

Date: 2026-11-23
Target: the chosen route in [`docs/architecture.md`](../architecture.md) (`opencode serve` HTTP + `GET /api/event` SSE)
Runtime checked: OpenCode v2.3.2, service bound to `127.0.0.1:28894`

## Scope and method

The bridge does not exist yet. This is a design-level review of the planned adapter against the official OpenCode v2 documentation, the live OpenAPI document, and the server running on this machine. Severity means risk to the host and user data, not bounty reportability.

Evidence gathered:

- `opencode --version` → `v2.3.2`; `opencode service status` → `http://127.0.0.1:28894`; listener owned by a local process only.
- Unauthenticated `GET /api/info` → `401 UnauthorizedError` ("Authentication required"). Auth is enforced out-of-band; the OpenAPI document declares no security schemes, so the spec alone is not evidence of safety.
- `GET /api/event` accepts a `types` query allowlist but has **no** `sessionID` filter.
- `POST /api/session/{id}/prompt` accepts `text`, `files`, `agents`, `skills`, `metadata`, `delivery`, `resume` (`additionalProperties: false`).
- Permission replies are limited to `once`, `always`, `reject`.

Trust boundary:

```text
untrusted:  text typed/pasted into Slop • model/tool output • anything the agent fetches
trusted:    Slop UI process • opencode.jsonc
boundary:   opencode serve (loopback, password-protected, full host authority)
```

## Findings

### CRITICAL — the approval path is a dead end

`docs/architecture.md` defers `permission.asked` / `permission.replied` to "the OpenCode TUI". A headless `opencode serve` has no TUI. Two failure modes follow:

- With the current global config (`shell` allowlist then `ask`, `external_directory` ask, `edit` allowlist then `ask`), any tool outside the allowlist emits `permission.asked` and waits for a reply nobody sends. The user sees a spinner until the 300 s timeout.
- With stock OpenCode, the base policy is `{ "action": "*", "resource": "*", "effect": "allow" }` and `external_directory` defaults to allow. A sentence typed into a floating pea could then run shell, write files, add MCP servers, and read credentials with no prompt.

The architecture document's claim that shell/external_directory are "ask by default" is false for stock OpenCode; it only holds because of local configuration. The bridge cannot assume that configuration exists.

Required: choose one explicit model — (a) a real approval surface using `permission.asked` plus `POST /api/session/{id}/permission/{requestID}/reply`, restricted to `once` / `reject` (never `always`, which persists a durable project-scoped allow rule), or (b) hard denies for all tool actions plus a dedicated least-privilege agent. A dangling `ask` with no resolver is not acceptable.

### HIGH — prompt JSON injection via string-built request bodies

If the adapter concatenates user text into a JSON string, input such as `x","files":[{"path":"C:\\Users\\example\\.ssh\\id_ed25519"}]` injects a valid `files` field and turns the input box into an arbitrary file-read primitive into model context. Build the body with `ConvertTo-Json` on a hashtable containing only `text`. Never interpolate untrusted text into JSON, a URL, or a shell string. Cap input length.

### HIGH — the input box is an untrusted prompt boundary

Even with correct JSON encoding, pasted content is untrusted instruction text and the agent has tools. The current global config allows all `webfetch`, `websearch`, `skill`, and `read`, with `external_directory` only `ask`. Use a dedicated agent with deny-by-default permissions instead of relying on model politeness. Add denies for private/link-local fetch targets (`127.0.0.1`, `localhost`, `169.254.169.254`, `file://`); the `webfetch` resource is the raw URL, so wildcard patterns are the only lever.

### HIGH — credential handling is unspecified; Basic auth is cleartext off-loopback

`opencode serve` prints a generated password; `OPENCODE_PASSWORD` pins a fixed one. Other HTTP clients use Basic auth with username `opencode`. The architecture document never says where the bridge gets it. Risks: hardcoded in `Slop.ps1`, passed on the command line (visible in process listings), or printed to logs. `opencode serve --hostname 0.0.0.0` sends that password in the clear over the network. Keep the bind loopback-only, read the password from the environment at runtime, never log it or put it in a URL, and use a dedicated serve password — it grants full API authority, not just chat.

### MEDIUM — the event stream is global, with no session filter

`GET /api/event` supports `?types=` but no `sessionID` parameter. Every session's text, tool output, `credential.updated`, `config.updated`, and plugin events reach the subscriber. Use a `types` allowlist limited to the mapped events, match `sessionID` by exact property equality (not substring), and never write raw event payloads to Slop logs or bubbles.

### MEDIUM — SSE has no replay, so a reconnect can silently lose the turn

The stream is live-only. A mid-stream drop has no catch-up; waiting for `session.idle` hangs until timeout. Subscribe before prompting (already in the design), and on EOF/disconnect re-fetch `GET /api/session/{id}/message` to reconstruct, then finalize using the existing "partial text followed by interruption" label.

### MEDIUM — the same API exposes direct RCE and data endpoints

`POST /api/shell`, `POST /api/session/{id}/shell`, `GET /api/fs/read/*`, `POST /api/experimental/fs/write`, `GET /api/credential`, `POST /api/experimental/mcp/{server}`, `POST /api/debug/heap-dump`. Anyone holding the Basic password has host authority. Treat that password like an SSH key. It is not confirmed whether these HTTP routes pass through the agent's tool-permission rules — do not assume they do. Keep permissions as defence in depth, not the primary barrier.

### MEDIUM — Stop may not stop side effects

Bridge-side SSE cancellation is proven. `POST /api/session/{id}/interrupt` stopping agent execution does not obviously kill background shell jobs, PTYs, or subagents. Verify live before calling Stop trustworthy. Fallbacks: `/api/experimental/job/{id}/cancel`, `/api/shell/{id}`, PTY routes.

### LOW — retention and size

One session per conversation is right, but the design never says when to delete it. Add `DELETE /api/session/{id}` on chat close/reset; OpenCode persists transcripts on disk. Cap input text and rendered delta/tool-output sizes so a long-running tray app cannot be memory-flooded. Keep CORS empty unless a browser client is added; then watch DNS rebinding and simple-request CSRF against loopback.

## What is already solid

- Loopback-only bind and mandatory password, verified live with a 401.
- One session per conversation, no 12-message resend: smaller leakage surface.
- Generation guard and token-aware `ReadLineAsync(token)` cancellation transfer directly to the bridge.
- No new visual states means no bypass of the four-colour / four-shape contract.
- A `types` allowlist exists on the event endpoint, which makes filtering cheap.

## Requirements before implementation

1. Correct the "ask by default" claim in `docs/architecture.md`.
2. Decide the approval model: real UI with `once` / `reject` only, or hard denies plus a dedicated agent. No dangling `ask`.
3. `ConvertTo-Json`, `text` field only, length cap, no interpolation anywhere.
4. `?types=` allowlist + exact `sessionID` match + no raw-event logging + reconnect recovery.
5. Loopback bind, environment-sourced password, nothing in argv/logs/URLs.
6. Live-verify interrupt against a spawned shell job.
7. Session deletion on teardown.

## Unverified — do not build on assumptions

- Whether `/api/shell` and `/api/fs/*` enforce tool permissions or bypass them.
- Whether interrupt terminates background jobs and PTYs.
- Whether `webfetch` blocks private/link-local ranges by default.
