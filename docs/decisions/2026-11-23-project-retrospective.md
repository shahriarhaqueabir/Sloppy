# Slop / Sloppy project retrospective (2026-11-23)

Scope: everything from the first motion overlay through the spring-membrane shell.
Source of truth for architecture remains `docs/architecture.md`; this report captures
which decisions earned their keep and the operating rules that follow from them.

## Current state

- Local `main` at `520333e`; no push, PR, deploy or CI changes.
- Slop is a WPF/PowerShell face for a running OpenCode service on `127.0.0.1:28894`.
  The `sloppy` agent supplies the companion persona; OpenCode owns sessions, tools,
  permissions and memory.
- Live-verified: idle pea, expand/collapse, amber thinking (`245,158,11`), green
  success (`34,197,94`), stream deltas, Stop cancellation, in-chat approvals,
  interrupt, window drag (`-66,-22` in the last probe) and clean process teardown.
- Headless: seven `tests/*-check.ps1` suites green; `verify.ps1` green.
- Visual shell: 484x330 window, 18 px goo margin, 32-point coupled-spring membrane,
  tanh-saturated bulge, hard window clamp, static rounded content clip.
- Not built: MCP servers (Phase 3), workflows/reminders/`slopsettings` (Phase 4).

## Best decision: Slop is the face, OpenCode is the brain and hands

Slop keeps the pea, signal language, chat surface and input pocket. It does not grow a
tool registry, permission engine, memory database, search client, browser driver or
workflow engine. A thin bridge translates OpenCode events into the signals Slop already
understands.

Why it was the best call:

- Five requested capabilities arrived through one local harness instead of five new
  PowerShell subsystems; capability growth is now config or an MCP server.
- One permission model to audit. Slop never persists an approval: cards reply `once`
  or `reject` only, even though main OpenCode has saved "always" grants that can
  short-circuit an `ask`.
- Failure modes stay isolated. The risk of experimental HTTP routes is confined to
  `Slop.OpenCode.ps1`; the character renderer stays untouched.

Alternatives rejected: building the tool stack inside Slop (months of duplicate work
and a second security surface), a fully local custom assistant (same stack problem,
lower capability ceiling), and a TypeScript rewrite (would discard the verified WPF
renderer for no capability gain). The TypeScript option remains viable only as a
different frontend later.

Trade-off accepted: Slop no longer works without `opencode serve`, and the visual
language can only say what four colors and four shapes can say.

## Other decisions that held up

1. **Lifecycle before bridge.** Phases, generation guards and a token-aware SSE
   reader were built first. Stop cancels HTTP read, the reader and
   `POST /api/session/{id}/interrupt`, rejects pending approvals and leaves the next
   request clean. This was the precondition for every later UI feature.
2. **Signal table is frozen.** Four colors, four shapes, no face/eyes/mouth/emoji.
   Every new OpenCode event maps onto an existing state. This kept the verifier and
   the character's identity intact through three visual rewrites.
3. **Geometry must be provably contained.** The demo's hard `Clamp` plus tanh
   saturation and a static rounded clip fixed the clipped edge, square-corner spill
   and staircase aliasing that softer tweaks could not.
4. **Headless green is not live green.** Three separate live audits found bugs that
   all headless suites missed: Stop not reaching the SSE reader, no `session.idle`
   after rejection, literal `__TOK__` markers, a blue dot caused by a missing
   password, and a ShowDialog crash from a variable-name collision.
5. **In-chat approvals, never `always`.** A headless service has no TUI to answer a
   dangling `ask`; the card plus generation-scoped rejection closes that hang.
6. **Local-only execution.** No subagents (explicit cost constraint), local commits,
   reversible edits with backups, never delete user work (`assets/` stays untracked).
7. **Defense in depth for the service.** Nine `webfetch` denies and credential-read
   denies mirrored in both configs; ASCII-only config content; backups before edits.
   The loopback bind and Basic auth remain the primary barrier.

## Do's

1. Run `verify.ps1` before claiming anything is done. For UI changes, also run
   `tools/verify-motion.ps1` and read its pixel/UIA output.
2. Dump raw SSE events against the installed OpenCode version before changing
   terminal-event handling; v2.3.2 emits `session.execution.interrupted` after a
   rejected permission and no `session.idle`.
3. Terminate every app the live verifier launches. An orphaned topmost `pwsh` holds
   inherited stdout handles and hangs piped callers for minutes.
4. Locate moving targets (the hopping pea) by rendered-pixel centroid, not fixed
   coordinates, and rescale probes from the live window rect for DPI.
5. Read `OPENCODE_PASSWORD` from `~/.config/opencode/service.json`; a verifier
   process without it makes every request fail before the thinking signal is set.
   Restart the service after the password changes, then wait for `/api/agent` to
   list `sloppy` before trusting live probes.
6. Publish state needed by PowerShell event handlers to script scope. Handlers
   registered with `Add_Tick`/`Add_Click` do not close over function locals, and
   `.GetNewClosure()` rebinding `$script:` breaks them.
7. Use native token-aware async APIs (`ReadLineAsync(token)`) for cancellation.
   Scriptblock delegates converted to .NET callbacks need a runspace and throw on
   threadpool/Timer threads.
8. Keep new module instances away from XAML `x:Name` values. In a top-level script
   `$script:Frame` and `$Frame` are the same variable; the engine is `$script:Membrane`.
9. Validate plan snippets (math, XAML, assertion order) in a temp location before
   committing an implementation plan.
10. Work in small phases with a commit at each verified boundary. Update docs and
    memory at the boundary, not at the end of a long single pass.
11. Assume saved "always" grants can override an agent `ask` rule. Prove a card path
    with a command that has no saved grant.

## Don'ts

1. Don't add a second tool, permission, memory or approval-persistence layer in Slop.
2. Don't add signal states, colors, shapes, a face, eyes, mouth or emoji.
3. Don't pass a cancellation token only to `SendAsync`; the SSE reader must see it.
4. Don't trust headless lifecycle/motion suites as proof that Stop, approvals or
   streaming work against the live backend.
5. Don't assume docs or dev source describe the installed API version.
6. Don't rely on `.GetNewClosure()` in PowerShell event handlers.
7. Don't use global `RenderOptions.EdgeMode="Aliased"` on curved vector paths.
8. Don't let silhouette points grow past the window edge; clamp in window space and
   keep content in a static clip rather than deforming it.
9. Don't put non-ASCII characters in `OPENCODE_CONFIG_CONTENT`; they are mangled by
   the OEM codepage.
10. Don't enable AgentShield without an explicit approval and a pinned version.
11. Don't push, open PRs, touch CI/CD, rotate credentials or delete user files in
    this workflow.
12. Don't dispatch subagents for this project (explicit cost constraint).

## Verification playbook

```powershell
# from the repo root
Get-ChildItem tests/*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
pwsh -NoProfile -File tools/verify-motion.ps1
pwsh -NoProfile -File ~/.agents/scripts/verify.ps1
pwsh -NoProfile -File ~/.agents/scripts/review.ps1   # advisory
pwsh -NoProfile -File ~/.agents/scripts/sign-out.ps1 -ProjectPath (Get-Location).Path
```

All seven headless suites plus `verify.ps1` must exit 0. A live verifier failure is a
real failure even when every headless suite is green.

## Next session

Start at Phase 3 (MCP servers). Keep the invariants above. Do not re-audit phases 0-2
unless a live probe fails; their status is recorded with evidence in `docs/architecture.md`
and in this report.
