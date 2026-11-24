# Build order (phases)

Status: current as of 2026-11-23. The original 2026-11-22 list (Ollama chat,
allowlisted function calling, UIA, vision, polish) was a pre-OpenCode plan and is
superseded by `docs/architecture.md`; it is kept here only as historical context.

Each phase: implement → headless checks → verify gate → live probe when UI changes →
local commit. No subagents — local execution only.

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Request lifecycle: phases, generation guard, cancellable SSE reader | done |
| 1 | OpenCode HTTP bridge: session, prompt, event translation, interrupt | done |
| 2 | `sloppy` agent, persona, workspace scope, hardening, in-chat approvals | done; live probes passed |
| 2b | Organic spring-membrane shell, 484x330 layout, live verifier | done; commit `520333e` |
| 3 | MCP servers for browser and Windows automation | planned — next |
| 4 | Multi-step workflows, reminders, `slopsettings` control panel | planned |

Phase 3 must keep the invariants: no second permission/memory/tool stack in Slop,
no new signal colors or shapes, and approvals stay `once`/`reject` only.
