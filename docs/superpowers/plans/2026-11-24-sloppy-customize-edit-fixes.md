# Sloppy Customize Editing Fixes Implementation Plan

> **For agentic workers:** Use `executing-plans` to implement this plan task by task. Preserve all existing staged work. Do not stage, commit, or push unless the user explicitly asks.

**Goal:** Make Customize edit and persist the companion's identity and persona, make Brain's route editor save changes, and keep cancel/error paths from changing the current configuration.

**Architecture:** Reuse the existing four-screen WPF onboarding wizard as an editor, prefilled from the current config and raw `persona.md`. Keep the wizard side-effect free and route both the destination buttons and tray actions through one validated save-and-apply path. Refresh the visible shell only after persistence succeeds; invalidate any prior OpenCode route evidence after a brain/provider/model change.

**Tech Stack:** PowerShell 7.6, WPF/XAML, existing `Slop.Config.ps1` persistence functions, Pester 6, existing UI Automation checks in `tools/verify-motion.ps1`.

---

## Scope and constraints

- The current `config.json` stores name, owner name, color, personality, and route settings. The full rendered persona is stored separately in `persona.md`; it does not preserve an extractable “custom text” fragment. Edit mode must therefore show the current full persona text.
- The wizard gathers a candidate only. It must not write either file until the user accepts the final screen.
- Cancel and Escape leave the saved config, persona, and visible shell unchanged.
- Never introduce provider credential fields. Paid-provider account connection remains in OpenCode.
- A route/provider/model change invalidates permission and provider-endpoint evidence. It must not retain an earlier disclosure acceptance for a different route.
- Keep the UI on the WPF dispatcher and keep file IO bounded; report persistence errors visibly without losing the previous in-memory config.

## Files and responsibilities

- Modify `src/Slop.Onboarding.ps1`: add explicit edit-mode input, preload the existing fields and raw persona, and return a validated candidate.
- Modify `src/Slop.ps1`: add edit actions to Customize and Brain; centralize save/apply; refresh shell summaries, color, autostart, and route indicators.
- Modify `tests/slop-onboarding-check.ps1`: test candidate values and cancel semantics.
- Modify `tests/slop-surfaces-check.ps1`: ensure each destination exposes a meaningful action and no credentials.
- Modify `tests/slop-shell-check.ps1`: guard save/apply wiring and route-evidence invalidation.
- Modify `tools/verify-motion.ps1`: exercise the actual edit, save, reopen, and cancel flows using isolated app data.
- Update `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md` with observed results and any remaining deferrals.

## Task 1: Define and test the edit-mode contract

**Files:**
- Modify: `src/Slop.Onboarding.ps1`
- Modify: `tests/slop-onboarding-check.ps1`

- [ ] **Step 1: Add an edit-mode input to the wizard**

Extend `Show-SlopOnboarding` with these parameters:

```powershell
param(
    [Parameter(Mandatory)][hashtable]$Config,
    [ValidateRange(1,4)][int]$StartScreen = 1,
    [switch]$EditMode,
    [AllowEmptyString()][string]$CurrentPersonaText = ''
)
```

Keep current first-run callers valid by making edit mode opt-in. In edit mode set the name, owner, color, personality, brain route, provider, model, agent, and capability controls from `Config`. Set `CustomBox.Text` to `CurrentPersonaText` and change its label/tooltip to say it edits the complete persona saved in `persona.md`.

- [ ] **Step 2: Add headless tests for candidate and cancel behavior**

Test the existing persona generator separately from edit mode. Add a testable helper, `New-SlopOnboardingCandidate`, with parameters `Config`, `EditMode`, `CurrentPersonaText`, `EditedPersonaText`, `CustomText`, and `SelectedColor`. Assert that edit mode returns the exact edited persona text; first-run mode still generates persona text from the preset plus `CustomText`; and canceled UI returns `$null` without calling persistence helpers.

- [ ] **Step 3: Preserve route choice when opening edit mode**

Set the screen-four radio buttons and text fields from the current config before displaying the wizard. A local/custom/bundled selection must reopen as the same selection, and paid OpenCode must reopen with its paid option selected. Add tests for each route without inserting secret values.

## Task 2: Add a single validated save-and-apply path

**Files:**
- Modify: `src/Slop.ps1`
- Modify: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Capture the previous persisted values before writing**

Add a helper that reads the current config and persona text before applying a candidate. Validate the candidate with `Test-SlopConfig` before any write. If validation fails, return a failure result and do not call `Write-SlopConfig` or `Write-SlopPersona`.

- [ ] **Step 2: Persist both files with rollback on failure**

Write the candidate config and full persona text. If either write fails, restore both previous values before returning failure. If restoration itself fails, include both failure reasons in the visible error and preserve the prior in-memory config. Add an injectable writer or function seam so tests can force the second write to fail and assert rollback.

- [ ] **Step 3: Refresh runtime state only after persistence succeeds**

After both writes succeed, replace `$script:SlopConfigResult.Config`; update `$script:IdentityBrush` and `$IdentityRing.Fill` using `Get-SlopIdentityColor`; rerun `Initialize-SlopDestinationPanels`; update the route badge and its Automation name/tooltip; and call `Sync-SlopAutostart` only if `autostart` changed. Do not change in-memory UI state on a failed save.

- [ ] **Step 4: Invalidate route-specific state on brain changes**

Compare the prior and candidate values of `brain`, `provider`, `providerTier`, `providerLocality`, `model`, `agentId`, `capabilityProfile`, and `openCodeBaseUrl`. If any differs, clear live route/permission evidence, reset disclosure acceptance for the changed route, and display `Unverified` until the route preflight proves its endpoint and permissions.

## Task 3: Wire Customize, Brain, and tray actions

**Files:**
- Modify: `src/Slop.ps1`
- Modify: `tests/slop-surfaces-check.ps1`
- Modify: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add an explicit Customize edit button**

Add `Edit companion` to `CustomizePanel`. Its handler calls `Show-SlopOnboarding -Config $script:SlopConfigResult.Config -CurrentPersonaText (Read-SlopPersona) -EditMode`, then sends a non-null result through the save-and-apply helper. Keep the existing displayed identity/persona values as a summary and refresh them after successful save.

- [ ] **Step 2: Make the Brain panel's Change brain action save**

Add `Change brain` to `BrainPanel`. Open the wizard at screen 4 in edit mode with current config and persona loaded. On successful result, use the same save-and-apply helper; on cancel, return without side effects.

- [ ] **Step 3: Route tray edit actions through the shared path**

Change “Edit personality” to open the wizard at screen 3 in edit mode and persist its accepted result through the shared save helper. Keep “Change brain” at screen 4 but route it through the same helper. Do not discard the returned result.

- [ ] **Step 4: Add static contract assertions**

Assert the Customize and Brain controls have Automation names, call the shared save helper for accepted results, and preserve existing settings on `$null` results. Assert no API-key, token, password, or client-secret input is present in the wizard.

## Task 4: Verify UI persistence in isolation

**Files:**
- Modify: `tools/verify-motion.ps1`
- Modify: `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md`

- [ ] **Step 1: Extend the existing disposable app-data setup**

Use the verifier's existing `SLOP_TEST_APPDATA` directory. Seed it with a known config and full persona text. Never point this test at the user's real `%LOCALAPPDATA%\Sloppy` directory.

- [ ] **Step 2: Exercise Customize save and reopen**

Through UI Automation, change the name, color, personality, and full persona text; accept; reopen Customize; and assert the displayed values, pea color, `config.json`, and `persona.md` match the accepted candidate.

- [ ] **Step 3: Exercise route save and cancel**

Change the selected brain/provider/model and accept; assert route evidence resets and the badge shows `Unverified` until preflight. Reopen Brain, change a value, press Escape, and assert the saved files and displayed route remain unchanged.

- [ ] **Step 4: Exercise write failure and cleanup**

Force the persona write to fail after config write begins. Assert config/persona rollback, unchanged runtime state, visible error, empty stderr, and clean disposal of the app and stand-in processes in `finally`.

## Task 5: Run focused and full verification

- [ ] **Step 1: Run focused suites**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-onboarding-check.ps1','tests/slop-surfaces-check.ps1','tests/slop-shell-check.ps1' -CI -Output Normal"
```

Expected: all focused tests pass, including edit prefill, saved candidate, cancel, persistence rollback, runtime refresh, and credential-field absence.

- [ ] **Step 2: Run parser and full project gates**

Parse all changed PowerShell files with `System.Management.Automation.Language.Parser`, then run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests' -CI -Output Normal"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
pwsh -NoProfile -File tools/verify-geometry.ps1
pwsh -NoProfile -File tests/slop-tour-check.ps1
pwsh -NoProfile -File tools/verify-motion.ps1
```

Expected: all commands exit 0, live UIA confirms persisted edits and canceled edits, and teardown leaves no app or model process from the run. Record any blocked environment-dependent check as deferred with its exact reason.

- [ ] **Step 3: Update status without overstating completion**

Update the verification report with exact commands, counts, and UI observations. Mark Customize complete only after save, reopen, cancel, rollback, and isolated live assertions pass. Do not stage or commit as part of this plan.

## Completion criteria

- Customize edits name, owner name, color, personality, full persona text, and brain choice.
- Brain changes route settings and invalidates old route evidence.
- Tray editing persists accepted results through the same save-and-apply path.
- Cancel, Escape, validation errors, and write failures preserve the previously saved and displayed values.
- No credential-entry controls or secrets are added.
