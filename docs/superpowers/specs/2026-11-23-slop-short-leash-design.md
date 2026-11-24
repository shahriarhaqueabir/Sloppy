# S.L.O.P. Short-Leash OpenCode Bridge Design

Status: approved on 2026-11-23 by the user.
Goal: connect Slop to `opencode serve` with deny-all-by-default tool permissions,
explicit per-action approval in the chat, and no path to unattended host access.

## Context

`docs/security/opencode-route-review.md` identified a critical design gap: the
architecture document deferred `permission.asked` to the OpenCode TUI, but a
headless `opencode serve` has no TUI. With stock defaults every action is allowed;
with the current global config, tools outside the allowlist wait forever for a
reply nobody sends. Either outcome is unacceptable for a floating desktop pea.

the user's decisions:

1. The leash lives in the Slop repo, not in the global OpenCode config.
2. Deny all by default. Only `read`, `glob`, `grep`, `websearch`, and `webfetch`
   are ever approvable; shell, edits, MCP, PTY, subagents, and external paths are
   hard-denied with no approval path.
3. Approval requests appear as a minimal card in the existing chat surface.

AgentShield scanning is explicitly deferred and is not part of this slice.

## Scope

In scope: a repo-scoped OpenCode config, a pure bridge-adapter module, the
approval card in `Slop.ps1`, the mapping from OpenCode events to the existing
lifecycle/signal path, headless tests, and live verification.

Out of scope: any change to the four colors, four shapes, signal table, motion,
character art, or provider/model selection. No new permission engine in Slop:
Slop only renders and answers OpenCode's own permission requests. No shell,
edit, MCP, skill, plugin, PTY, subagent, or automation capability is added.

## Architecture

```text
.opencode/opencode.jsonc   NEW  deny-all config + dedicated primary agent
src/Slop.Lifecycle.ps1     unchanged  phases, generation guard, SSE parsing, cancel
src/Slop.OpenCode.ps1      NEW  pure helpers: config checks, JSON bodies, event filter
src/Slop.ps1               wire transport, approval card, session teardown
tests/slop-opencode-check.ps1  NEW  headless assertions for the rules and helpers
docs/architecture.md       update stale default/approval claims
```

`Slop.OpenCode.ps1` must stay importable headlessly. `Slop.ps1` cannot be imported
by tests because loading it constructs a WPF window.

## Control plane

The config file is strict JSON (no comments, no trailing commas) so tests can
parse it directly with `ConvertFrom-Json`.

Agent rules are appended after global rules, so project-level permissions alone
would lose to the global config. The leash therefore uses a dedicated primary
agent whose own rules are appended last:

```json
"agents": {
  "slop-short-leash": {
    "description": "Read-only, approval-gated agent for the Slop bridge",
    "mode": "primary",
    "permissions": [
      { "action": "*",        "resource": "*", "effect": "deny" },
      { "action": "read",     "resource": "*", "effect": "ask"  },
      { "action": "glob",     "resource": "*", "effect": "ask"  },
      { "action": "grep",     "resource": "*", "effect": "ask"  },
      { "action": "websearch","resource": "*", "effect": "ask"  },
      { "action": "webfetch", "resource": "*", "effect": "ask"  },
      { "action": "webfetch", "resource": "*127.0.0.1*",     "effect": "deny" },
      { "action": "webfetch", "resource": "*localhost*",     "effect": "deny" },
      { "action": "webfetch", "resource": "*169.254.169.254*","effect": "deny" },
      { "action": "webfetch", "resource": "*file://*",       "effect": "deny" }
    ]
  }
}
```

Project policies hard-deny what no approval may unlock. Broad deny first, lifts
next, specific denials last, because the last matching statement wins. A `deny`
here beats an `ask` and even a saved "Allow always" approval:

```json
"policies": [
  { "action": "tool.use", "resource": "*", "effect": "deny" },
  { "action": "tool.use", "resource": "read:*",      "effect": "allow" },
  { "action": "tool.use", "resource": "glob:*",      "effect": "allow" },
  { "action": "tool.use", "resource": "grep:*",      "effect": "allow" },
  { "action": "tool.use", "resource": "websearch:*", "effect": "allow" },
  { "action": "tool.use", "resource": "webfetch:*",  "effect": "allow" },
  { "action": "tool.use", "resource": "webfetch:*127.0.0.1*",      "effect": "deny" },
  { "action": "tool.use", "resource": "webfetch:*localhost*",      "effect": "deny" },
  { "action": "tool.use", "resource": "webfetch:*169.254.169.254*", "effect": "deny" },
  { "action": "tool.use", "resource": "webfetch:*file://*",        "effect": "deny" },
  { "action": "tool.use", "resource": "external_directory:*", "effect": "deny" },
  { "action": "tool.use", "resource": "shell:*", "effect": "deny" },
  { "action": "tool.use", "resource": "edit:*", "effect": "deny" },
  { "action": "tool.use", "resource": "write:*", "effect": "deny" },
  { "action": "tool.use", "resource": "patch:*", "effect": "deny" },
  { "action": "tool.use", "resource": "subagent:*", "effect": "deny" },
  { "action": "mcp.use", "resource": "*", "effect": "deny" },
  { "action": "skill.use", "resource": "*", "effect": "deny" },
  { "action": "plugin.use", "resource": "*", "effect": "deny" }
]
```

`integration.connect`, `integration.use`, `websearch.use`, and `provider.use`
are deliberately untouched: a broad `integration.use` deny would also remove
the model the bridge needs. The leash controls tools, not model availability.

The bridge must refuse to start a turn if config validation fails: baseline deny
rule absent, any hard-deny missing, or an additional approvable action present.
The reply builder itself rejects every decision except `once` and `reject`.

## Bridge request path

1. `POST /api/session` → store `sessionID`.
2. `POST /api/session/{sessionID}/agent` with `{"agent":"slop-short-leash"}`.
   Fail closed if this does not succeed; never prompt a session still on `build`.
3. Subscribe `GET /api/event?types=<allowlist>` **before** prompting:
   `session.text.delta`, `session.step.first-token`, `session.text.started`,
   `session.text.ended`, `session.execution.succeeded`,
   `session.execution.failed`, `session.execution.interrupted`, `session.idle`,
   `permission.asked`, `permission.replied`.
4. `POST /api/session/{sessionID}/prompt` with a body produced by `ConvertTo-Json`
   from `@{ text = $text }` only. No string interpolation into JSON, URLs, or
   shell; input length capped.
5. Every event is accepted only on exact `sessionID` property equality. Raw event
   payloads are never logged or rendered wholesale.
6. `DELETE /api/session/{sessionID}` on chat close or reset.

Authentication: loopback bind only; password read from `OPENCODE_PASSWORD` at
runtime; Basic username `opencode`; never in argv, URLs, config files committed
to this repo, or logs.

## Approval flow

`permission.asked` carries a request ID, action, and resource. The bridge stores
them with the current generation and enqueues an approval card into the chat:
truncated action/resource text plus `Allow once` and `Reject`.

Reply is `POST /api/session/{sessionID}/permission/{requestID}/reply` with
`decision` of `once` or `reject` only. `always` is never emitted by any code path.
The signal glyph keeps its current state; the card is an ordinary chat element,
not a new visual signal.

Collapse, Stop, generation change, stream cancel, or disconnect rejects every
pending request for that generation and posts `/interrupt`. Late replies from a
previous generation are dropped by the existing generation guard.

## Failure and cancellation

The `types` allowlist keeps credential/config/tool events out of the UI. SSE has
no replay, so on disconnect the bridge re-fetches `GET /api/session/{id}/message`
to reconstruct, then finalizes with the existing "partial text followed by
interruption" label. All reader/stream/response/client disposal and the
token-aware `ReadLineAsync(token)` cancellation come from `Slop.Lifecycle.ps1`
unchanged. Stop also rejects pending approvals so no agent waits on a card that
will never be answered.

## Testing

`tests/slop-opencode-check.ps1` (headless, no WPF, no network):

- config parses; agent mode is `primary`; baseline deny is present and first;
  only the five read actions resolve to `ask`; all hard-deny policies exist;
- the permission reply builder rejects `always` and every other decision;
- prompt body builder uses `ConvertTo-Json` and emits only `text`; an injection
  payload containing `","files":[{"path":"..."}]` stays inside the `text` value;
- event classifier rejects wrong `sessionID`, event types outside the allowlist,
  and malformed payloads;
- permission reply builder accepts only `once` / `reject`.

Existing suites must stay green: `slop-lifecycle-check.ps1`, `slop-motion-check.ps1`,
the `verify` gate, and `tools/verify-motion.ps1`.

Live checks against `opencode serve` from the Slop repo:

- unapproved read produces a card; `Reject` returns no content;
- `Allow once` returns content exactly once; a repeat request asks again;
- shell attempt fails with `Blocked by configuration policy` and produces no card;
- Stop mid-approval rejects the pending request, finalizes the UI, and the next
  request completes cleanly.

## Risks and trade-offs

- A repo-scoped config can be overridden by a future global policy; the headless
  config check is the tripwire, and the bridge fails closed if validation fails.
- `webfetch` blocking uses wildcard URL patterns, not an IP-range parser: link
  local in unusual notation may slip through. Hard-deny policies cover the common
  forms; this is accepted for the short-leash slice.
- An in-chat approval card adds one interactive element to the chat surface. It
  reuses existing bubble styling and introduces no new signal state.
- Interrupt-to-child-process termination is still unverified; if a live check
  shows side effects surviving Stop, that becomes a separate finding, not a
  silent assumption in this slice.
