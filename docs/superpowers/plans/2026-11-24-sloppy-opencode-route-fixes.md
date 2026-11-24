# Sloppy OpenCode Route Fixes Implementation Plan

> **For agentic workers:** Use `executing-plans` to implement this plan task by task. Keep the changes on a dedicated local branch or isolated worktree so the currently staged product-v1 work is preserved. Do not commit or push unless the user explicitly asks.

**Goal:** Make the OpenCode route usable only after runtime compatibility and permission verification, and show route locality honestly.

**Architecture:** Add a read-only OpenCode preflight that discovers the active version, agent/model/provider endpoint, and effective permission state against a disposable-service contract. Feed fresh evidence into the existing fail-closed route planner without blocking the WPF dispatcher. Represent unknown locality explicitly until endpoint discovery proves local or remote.

**Tech Stack:** PowerShell 7.6, WPF/XAML, OpenCode HTTP API pinned to 2.3.2, Pester 6, existing `tools/verify-motion.ps1` live UI harness.

---

## Scope and constraints

- Preserve the existing report of prior test results as historical evidence. New results must record the exact command, environment isolation, exit code, and output summary.
- Never probe or alter the shared OpenCode service. Runtime/API integration tests use a disposable service with a private config directory, database, port, and credential, supplied by the test harness.
- Do not put service passwords, API keys, or credentials in Sloppy config, persona files, logs, command-line arguments, or UI fields.
- Permission evidence is short lived and bound to the exact service URL, selected agent, provider, model, endpoint, permission profile, and observation time. Missing, stale, mismatched, or incomplete evidence blocks the send.
- Provider locality is based on observed provider endpoint data. User configuration is only a preference and must not be rendered as verified fact.
- Keep network calls off the WPF dispatcher. Reuse the existing worker/queue pattern and generation checks.

## Files and responsibilities

- Modify `src/Slop.OpenCodeCompat.ps1`: define the pinned compatibility contract and validate observed service version/API evidence.
- Create `src/Slop.OpenCodeProbe.ps1`: read-only, bounded OpenCode preflight; normalize version, provider endpoint, agent/model selection, live rules, saved grants, and effective hard-deny policies into the evidence shape consumed by `src/Slop.Route.ps1`.
- Modify `src/Slop.Route.ps1`: support an explicit unverified locality state, validate probe evidence, preserve fail-closed behavior, and avoid declaring a route ready before the probe succeeds.
- Modify `src/Slop.ps1`: schedule the probe in a worker, display pending/unverified/verified route status, and show disclosure before the first remote send.
- Modify `tests/Slop.Tests.ps1` and focused suites under `tests/`: register and test compatibility, probe normalization, route gating, and locality labels.
- Modify `tools/verify-motion.ps1`: add disposable OpenCode preflight and live UI route assertions; keep teardown in `finally`.
- Update `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md` after the code work with newly observed results and remaining deferrals.

## Task 1: Capture the real disposable OpenCode API contract

**Files:**
- Modify: `src/Slop.OpenCodeCompat.ps1`
- Modify: `tests/slop-opencode-compat-check.ps1`
- Modify: `tools/verify-motion.ps1` only if its disposable service setup needs a safe read-only probe helper

- [ ] **Step 1: Start only a disposable service and record its identity**

Use the existing live verifier's disposable service setup. Confirm its private config directory, database, loopback port, and generated credential are distinct from the user's service. Store sensitive values only in process environment and memory.

- [ ] **Step 2: Probe safe read-only endpoints**

Query the pinned service's configuration/version, agents, models, providers, saved permissions, and effective configuration surfaces. Record status codes and sanitized response shapes, excluding credentials, user paths, session contents, and prompt text.

- [ ] **Step 3: Confirm what the service exposes for each required API operation**

Compare the service's published API description, if available, with every method and route in `Get-SlopOpenCodeCompatContract`. Do not claim GET probes verify POST, DELETE, or interrupt operations. Exercise mutating routes only with a disposable session and test data, then delete that session and confirm teardown.

- [ ] **Step 4: Make the contract match observed evidence**

Keep version and method/path entries only when verified against the pinned disposable service. Add tests for malformed version data, missing routes, unsupported versions, and incomplete route evidence. Return reasons that identify the missing operation without including secrets.

- [ ] **Step 5: Record probe evidence**

Save sanitized command/results in the verification report. Mark the compatibility contract verified only when the disposable probe covers every required operation, not merely when synthetic fixtures satisfy the helper.

## Task 2: Implement a read-only OpenCode preflight and runtime compatibility gate

**Files:**
- Create: `src/Slop.OpenCodeProbe.ps1`
- Modify: `src/Slop.OpenCodeCompat.ps1`
- Modify: `src/Slop.Provider.ps1`
- Modify: `src/Slop.Route.ps1`
- Create: `tests/slop-opencode-probe-check.ps1`
- Modify: `tests/slop-route-check.ps1`

- [ ] **Step 1: Define the normalized evidence record**

Use a hashtable with these exact keys: `Source`, `BaseUrl`, `Version`, `AgentId`, `ProviderId`, `Model`, `ProviderEndpointUrl`, `ObservedAtUtc`, `LiveRules`, `SavedGrants`, and `EffectivePolicies`. `Source` must equal `live-api`; `ObservedAtUtc` must be UTC ISO-8601. Never persist this record to config or disk.

- [ ] **Step 2: Add probe tests using a loopback mock service**

Cover successful normalization; non-2xx responses; malformed JSON; missing version, agent, provider, endpoint, or permission surfaces; unsupported version; redirect to a non-loopback host; and request timeout. Assert that failures return no evidence and contain no auth header, response body, or secret in error text.

- [ ] **Step 3: Implement bounded read-only requests**

Implement `Get-SlopOpenCodeRouteEvidence` with explicit `BaseUrl`, `Auth`, selected agent/provider/model, and timeout parameters. Accept only loopback HTTP, disable automatic redirects, cap response sizes, enforce the selected timeout, and use GET requests only. Normalize actual response fields using the fixtures captured in Task 1. Do not invent API field names from config files.

- [ ] **Step 4: Gate the route with live evidence**

Have `Get-SlopStreamPlan` pass the normalized evidence to `Test-SlopEffectivePermissions` and verify all existing bindings: exact service, agent, provider, model, endpoint, timestamp freshness, expected profile rules, no saved grants, and effective hard denies. `ReadyToSend` remains false for every missing or failed condition.

- [ ] **Step 5: Register and run focused tests**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-opencode-probe-check.ps1','tests/slop-opencode-compat-check.ps1','tests/slop-route-check.ps1' -CI -Output Normal"
```

Expected: all focused tests pass, including fail-closed cases; no test contacts a shared service.

## Task 3: Wire the preflight into WPF without blocking the dispatcher

**Files:**
- Modify: `src/Slop.ps1`
- Modify: `src/Slop.Provider.ps1`
- Modify: `tests/slop-shell-check.ps1`
- Modify: `tests/slop-provider-check.ps1`
- Modify: `tools/verify-motion.ps1`

- [ ] **Step 1: Add a worker preflight phase**

For OpenCode sends, start a worker that probes route evidence and compatibility before constructing a sendable adapter plan. Return a typed queue marker containing only normalized, nonsecret evidence or a sanitized failure. Keep the UI responsive and associate each result with the request generation so stale results cannot update the active UI.

- [ ] **Step 2: Keep the prompt behind verification and disclosure**

Do not create a session or POST a prompt while compatibility or permissions are unverified. Once the preflight verifies the route, update the badge. If the observed provider endpoint is remote, show the existing disclosure and require acceptance before sending. A local endpoint does not require remote disclosure. Cancellation sends no prompt.

- [ ] **Step 3: Verify request lifecycle behavior**

Add static and focused tests proving that stale, failed, or canceled preflight results cannot start the adapter; Stop cancels the worker; no prompt is sent before disclosure acceptance; and only the active request generation updates the UI.

- [ ] **Step 4: Run the disposable live route check**

With a disposable OpenCode service and stand-in provider, record success for the supported version and refusal for a mismatched version, missing hard deny, saved grant, stale evidence, and endpoint mismatch. Confirm no user service/config is read or modified.

## Task 4: Show verified, unverified, and remote locality accurately

**Files:**
- Modify: `src/Slop.Route.ps1`
- Modify: `src/Slop.ps1`
- Modify: `src/Slop.Disclosure.ps1` if copy needs a separate unverified state
- Modify: `tests/slop-route-check.ps1`
- Modify: `tests/slop-disclosure-check.ps1`
- Modify: `tools/verify-motion.ps1`

- [ ] **Step 1: Add an explicit unverified route state**

When OpenCode is selected but the provider endpoint has not been observed, render `Unverified · <provider> · <model>` in the header badge and Privacy panel, both at startup and during a send. Do not use `Remote` based only on an empty endpoint and do not use config `providerLocality` as proof. Keep sends blocked until route and permission preflight succeeds.

- [ ] **Step 2: Derive locality from the observed endpoint**

After valid evidence arrives, classify only a loopback HTTP(S) provider endpoint as local. Classify a valid non-loopback provider endpoint as remote, subject to the service/API validation rules. Reject malformed, credential-bearing, or unsupported endpoints and return to unverified.

- [ ] **Step 3: Test every displayed state**

Assert that configured-local with no evidence is unverified, observed-loopback is local, observed-remote is remote and disclosure-gated, invalid evidence is unverified and not sendable, and changing provider/model invalidates stale evidence and the old badge.

- [ ] **Step 4: Verify the live badge and gate**

Run the disposable live verifier and capture UI Automation names/text for each state. Confirm the remote disclosure appears before prompt send and cancel leaves the route visible while sending nothing.

## Task 5: Run route gates and update the verification report

**Files:**
- Modify: `tools/verify-motion.ps1`
- Modify: `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md`

- [ ] **Step 1: Run focused tests and parser checks**

Run focused suites for the probe, route, and shell, then parse every changed PowerShell file with `System.Management.Automation.Language.Parser`. Record exact counts and exit codes.

- [ ] **Step 2: Run the full project gates**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests' -CI -Output Normal"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
pwsh -NoProfile -File tools/verify-geometry.ps1
pwsh -NoProfile -File tests/slop-tour-check.ps1
pwsh -NoProfile -File tools/verify-motion.ps1
```

Expected: all commands exit 0; the live verifier demonstrates local, remote, unverified, disclosure-cancel, and clean-teardown scenarios. If an environment-dependent scenario cannot run, record it as deferred with its exact blocker.

- [ ] **Step 3: Rewrite the status summary from observed results**

State separately which Phase 1, bundled-local, OpenCode runtime, locality, installer, memory-budget, and publication items are complete, deferred, or user-owned. Link the separate customization plan. Label previous counts as historical if not rerun. Do not claim that the public snapshot exists unless it is located and its file count, `.git`/`.memory` absence, and PII scan are checked again.

- [ ] **Step 4: Review without staging or committing**

Run `git diff --check`, inspect the focused diff, and confirm that only intended source, test, verifier, and report paths changed. Leave staging and commits to the user.

## Completion criteria

- The app calls the compatibility/preflight path before any OpenCode send.
- OpenCode remains blocked on unsupported version, missing/stale evidence, saved grants, broad allows, or absent effective hard-deny rules.
- The badge says `Unverified` until endpoint evidence establishes actual locality.
- Remote disclosure is accepted before any remote prompt is sent; cancel sends nothing.
- The updated report claims only work and checks supported by current code and fresh evidence.
