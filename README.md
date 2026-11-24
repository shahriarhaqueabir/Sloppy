<p align="center">
  <img src="assets/sloppy.png" alt="Sloppy, a small desktop companion" width="320">
</p>

# Sloppy

**A tiny desktop companion that makes your local coding agent visible — and easier to trust.**

Sloppy sits on your desktop as an animated pea. It changes colour, shape and motion with what your agent is actually doing: thinking, working, waiting on a tool, stalled, asking permission, or finishing a reply. When OpenCode asks for approval, the decision appears in the chat as **Allow / Allow once / Reject** instead of hiding in a log.

It is local-first and quiet. There is no cloud account, no telemetry, and no model bundled here. You bring your own [OpenCode](https://opencode.ai/) setup; Sloppy is the face and the permission surface for it, talking to a local service over loopback HTTP.

## Why you might want it

- **See the state, don't guess it.** One resolved signal drives colour, shape, particles and pulse, so the companion cannot disagree with the agent it represents.
- **Approvals where you are.** Permission requests become in-chat cards with generation guards, so a late click cannot approve a newer turn.
- **Stop means stop.** Cancellation reaches the streaming reader itself, not just the initial request.
- **Small and inspectable.** A WPF / PowerShell frontend with headless tests, a live UI verifier and an 18-step source CodeTour.

## Quick start

There is no installer yet. The honest current path is:

```powershell
pwsh -STA -File src/Slop.ps1
```

Requirements:

- Windows
- PowerShell 7.6 or later, in STA mode
- A local OpenCode service with your agent, model and provider configured

Sloppy prefers whatever OpenCode config you already have. If there is none, it installs a minimal zero-trust config; it never overwrites an active one.

## What it is not

Sloppy is a desktop frontend, not a model, a standalone chatbot, or a hosted service. Sessions, tools, providers and permissions belong to OpenCode. That boundary is deliberate: one broker owns capability, so the UI never has to guess what a model is allowed to do.

The companion product is still early. Some ideas in [the plans](docs/superpowers/plans) are directions, not shipped features. The release notes and [verification report](docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md) keep the verified and deferred work separate.

## Proof

```powershell
# Full Pester aggregate — 522 tests
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Detailed"

# Geometry verifier — 18 scenarios
pwsh -NoProfile -File tools/verify-geometry.ps1

# Live UI verifier: expand, maximize, send, stream, drag, collapse
pwsh -NoProfile -File tools/verify-motion.ps1
```

The tour guard checks all source anchors, so the architecture walkthrough cannot silently drift away from the code.

## Read more

- [Architecture](docs/architecture.md)
- [Technical showcase](docs/SHOWCASE.md)
- [18-step architecture CodeTour](.tours/architect-slop-architecture.tour)
- [Provider security architecture](docs/superpowers/specs/2026-11-23-sloppy-provider-security-architecture.md)

## License

MIT — see [LICENSE](LICENSE). The desktop icon is included as `assets/sloppy.ico`.
