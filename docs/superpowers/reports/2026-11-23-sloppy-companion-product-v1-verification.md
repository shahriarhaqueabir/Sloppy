# Sloppy companion product v1 — verification report

Date: 2026-11-24
Scope: Phase 1 headless foundation + Phase 2 WPF/route/privacy wiring from the approved
`docs/superpowers/plans/2026-11-23-sloppy-companion-product-v1.md`.
No commits, push, remote, deploy or CI/CD changes were made by the agent. The user owns all commits.

## Review status (2026-11-24)

The earlier “Phase 1 + Phase 2 done” wording overstated completion. The staged work contains the
Phase 1 foundation and part of Phase 2: the four destination panels, disclosure and route display
scaffolding, controlled permission-profile generation, and bundled-model worker startup. It does not
complete a usable OpenCode send path or a fully editable Customize destination.

- **Phase 1 foundation:** implemented. The verification results below are those recorded during the
  implementation; they were not rerun during this report review.
- **Phase 2 WPF and bundled route:** partially implemented. The live run recorded in section 1.6
  exercises the bundled local route, destination panels, window behavior, and a local reply.
- **OpenCode:** route, disclosure, permission-profile, and compatibility scaffolding exists, but the
  app does not invoke `Test-SlopOpenCodeCompatContract`, and `Start-Stream` does not supply the live
  provider-endpoint or permission evidence required by `Get-SlopRoutePlan`. OpenCode sends therefore
  fail closed. The disposable-service run recorded below does not verify OpenCode chat compatibility
  or effective permissions.
- **Customize:** the panel displays the saved identity and persona values. It does not edit them.
  The tray’s “Edit personality” action opens the wizard at its personality screen and discards the
  returned result instead of saving it; name, color, and persona are not editable through that path.
- **OpenCode route label:** at startup the badge and Privacy panel can use the configured locality
  preference as though it were observed. During send planning, the missing endpoint observation
  causes the route planner to classify OpenCode as remote. The badge can therefore misstate locality
  before sending and then change. Until endpoint discovery is wired, show “Unverified” in both places.
- **Source checkout:** the current `main` branch has an `origin` remote and its reachable history
  includes personal paths and references to another person's identity. The staged index also includes `.memory/state.md`
  and `.opencode/opencode.jsonc`. Do not commit/push this checkout as the public repo or push its
  history. The five pre-existing untracked files (four docs and one `.memory` topic) were left
  untouched. This review added this report edit and two new untracked plans.
- **Earlier publish snapshot:** `sloppy-public-v1-20261124/` was found under the local temp
  `opencode` folder. It has 91 files, no `.git`, and no `.memory`, but it contains two `.opencode`
  configuration files and two screenshots of the development desktop. It is not safe to publish as
  is.
- **Audited commit candidate:** a separate `sloppy-public-v1-audited-20261124/` staging repo was
  created under the same local temp folder. It has 89 staged files, an empty Git history, no remote,
  and excludes `.memory`, `.opencode`, and the two desktop screenshots. It includes this corrected
  report and the two follow-up code-fix plans. The exact staged index scan found no Jes‑e identifier,
  user machine path, key/token pattern, credential file, `.memory`, or `.opencode` file. The only
  personal-name matches are the previously accepted MIT attribution and its quoted documentation;
  `C:\Users\example` occurrences are synthetic placeholders. No password value was found; matches
  are code that obtains a password at runtime and clearly synthetic test examples. The README no
  longer requires a repo-local OpenCode config. Do not add a remote to this staging repo until you
  have reviewed its staged contents yourself.
- **Next work:** use `docs/superpowers/plans/2026-11-24-sloppy-opencode-route-fixes.md` for runtime
  compatibility, route evidence, and truthful locality; use
  `docs/superpowers/plans/2026-11-24-sloppy-customize-edit-fixes.md` for editable customization and
  persistence.

## 1. What was verified, with exact commands and results

### 1.1 PowerShell parse checks

```
pwsh -NoProfile -Command '$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile(''src/Slop.ps1'',[ref]$t,[ref]$e); if($e.Count){$e|ForEach-Object{$_.Message};exit 1}; ''parse ok'''
pwsh -NoProfile -Command '$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile(''tools/verify-motion.ps1'',[ref]$t,[ref]$e); if($e.Count){$e|ForEach-Object{$_.Message};exit 1}; ''parse ok'''
```

Result: `parse ok` for both files, exit 0. All changed PowerShell files were parsed with
`Parser.ParseInput`/`ParseFile` during the phase; no syntax errors remain.

### 1.2 Full headless suite (direct)

```
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests' -CI -Output Normal"
```

Result: `[+] tests/Slop.Tests.ps1 (530 tests)`, `Tests Passed: 530, Failed: 0, Skipped: 0`, exit 0.
The dynamic aggregator `tests/Slop.Tests.ps1` dot-sources every `tests/*-check.ps1`, so all headless
suites ran, including the new config/disclosure/onboarding/provider/route/surfaces/local-model/
OpenCode-compat/profile suites.

Targeted suites after the final source edits: shell 129/129, provider 10/10, config 15/15,
route 11/11, onboarding 7/7. Earlier phase gate: 21 suites, 502 tests, 0 failed.

### 1.3 Mandatory verify gate

```
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
```

Result: three Pester files discovered (main worktree 530 tests, two existing user worktrees 441 and 486),
`Tests Passed: 1457, Failed: 0`, `PASS`, `=== VERIFY COMPLETE === All gates passed.`, exit 0.
The worktree tests are pre-existing user work and were not modified.

### 1.4 Geometry gate

```
pwsh -NoProfile -File tools/verify-geometry.ps1
```

Result: `scenarios=18 failures=0`, exit 0. All edge-margin, content-inset, corner, asymmetry and
reduced-motion scenarios passed; contact sheet written to the local temp directory (not staged).

### 1.5 Architecture tour anchors

```
pwsh -NoProfile -File tests/slop-tour-check.ps1
```

Result: `Tests Passed: 38, Failed: 0`, exit 0. Three anchors had drifted after the UIA-name and
worker-start edits; they were refreshed to the current exact lines:
`function Start-Stream` 1261→1264, `function Add-SlopApprovalCard` 1115→1118,
`MotionTimer` 1592→1619. No tour content claims were weakened.

### 1.6 Live verifier (disposable service, stand-in brain)

```
$env:SLOP_LIVE_RUNTIME_DIR='<local llama.cpp bin directory>'
$env:SLOP_LIVE_MODEL_FILE='<local 9B chat GGUF>'
pwsh -NoProfile -File tools/verify-motion.ps1
```

Result: exit 0, no stderr, clean teardown. Key observations:

- `STANDIN` created from caller-supplied env vars only; no machine-specific paths are stored in the repo.
- `DISPOSABLE service port=... pid=...` — a private OpenCode service with its own port, config dir,
  config file, database and password. The shared service was never used and `service.json` credentials
  were never read.
- `BADGE text=Local · bundled · Qwen3 4B Q4_K_M` — the header badge shows the real route.
- `DEST buttons=Settings|Customize|Brain|Privacy`, all four panels open with marker text on-screen.
- `PRIVACY route=Route: Local · bundled · ...` and three distinct deletion-scope copies.
- Maximized `1200x1920` into a `1200x1920` work area: ChatScroll, InputBox and SendBtn all inside.
- `SEND input='Reply with the single word OK.' enabled=True`, after click `input='' stopVisible=True`.
- `SIGNAL thinking dot observed = amber`, `STREAM changes=3 ... errorRed=0`,
  `SIGNAL success dot=34,197,94 color=green`, `SIGNAL successSeen=True`.
- `ESC panel=51,51,51` (collapse), `DRAG moved=-66,-22 flag=True`, `APP OUT:`/`APP ERR:` empty,
  `TEARDOWN complete`, no orphan `pwsh` or `llama-server.exe` from this run.

`SLOP_TEST_APPDATA` isolates Sloppy config/persona from real user data. `LOCALAPPDATA` was pointed at
the disposable stand-in tree only for the app process and restored in `finally`.

This run proves the bundled local chat path and listed UI behavior. Starting a disposable OpenCode
service as test infrastructure does not prove that Sloppy exercised OpenCode chat, the pinned API
surface, provider discovery, or effective permissions. Those OpenCode checks remain deferred.

### 1.7 Live defect found and fixed during this phase

The first bundled-route live run reached `SIGNAL thinking dot observed = amber` but never produced
green. UIA text and direct model-health probes confirmed the stand-in model served
`GET /health` with 200, yet the app's adapter got `connection refused`. Root cause: `Get-SlopRoutePlan`
correctly reported `NeedsLocalModelStart`, but `Start-Stream` never started the bundled model, so the
adapter raced a closed port. Fixes, all written RED-first as static assertions:

- `src/Slop.ps1` passes `-LocalModelProcess $script:LocalModelProcess` into `Get-SlopStreamPlan`.
- The adapter thread job dot-sources `Slop.LocalModel.ps1` and calls `Start-SlopLocalModel` before
  sending, queueing `__SLOPMODEL__<pid>` so the UI thread can own and cleanly stop the process.
- Guards added in `tests/slop-shell-check.ps1` (3 assertions) and `tests/slop-provider-check.ps1`
  (contract assertions on `NeedsLocalModelStart`, `LocalModelPaths`, `ReadyToSend`).

The final live run above is green after this fix. This is the same class of defect the headless suites
could not catch — green unit tests are not live proof.

### 1.8 PII / history scrub scan

```
git grep -n -I -E 'shahr|Users[\\/]shahr|E:[\\/]Projects|/home/shahr|sk-[A-Za-z0-9]{10}|ghp_[A-Za-z0-9]{10}|AKIA[A-Z0-9]{12}' -- .
```

Result: four matches, all intentional: `LICENSE:3` (`Copyright (c) 2026 shahr`), the quoted copy in
`docs/superpowers/plans/2026-11-23-sloppy-portfolio-showcase.md:71`, and two mentions of that quoted
copy in the companion spec and plan. No personal machine path, credential, or secret was introduced by
the Phase 1/2 modules. The live verifier's stand-in paths are supplied by environment variables at
run time, never written into tracked files.

The original 91-file history-free snapshot was located and checked. It has no `.git` or `.memory`, but
does contain `.opencode/opencode.jsonc` and `.opencode/opencode.jsonc.muted`, which are local agent
configuration and are excluded from the audited candidate. The two captured screenshots also show a
PowerShell window and desktop background; they are excluded until recaptured on a clean desktop. The
audited 89-file candidate is a separate empty-history repository with no remote. Its staged tree was
scanned; only the accepted attribution, synthetic home-path placeholders, and nonsecret password
handling code/test examples matched the audit patterns.

The previously accepted public snapshot (`sloppy-public/`, 68 files, no `.git`, no `.memory`) retains the
a personal alias in a handful of historical design/ADR docs. That alias was present in the accepted
snapshot from the earlier scrub pass and was left unchanged in this phase. If it should be removed from
the public artifact, that is a separate user-owned decision affecting historical docs.

## 2. Deferred register — not claimed as verified

| Item | Status | Why / owner |
|---|---|---|
| Task 7 Step 1 onboarding live assertions (four screens, swatch → `PreviewPea.Fill`, preset → `SampleLine.Text`, writes `config.json`/`persona.md`, semantic dot stays `#3B82F6`) | Deferred | Onboarding module has a 7/7 headless suite, but the live verifier currently starts from an already-onboarded isolated config. Extending the live flow is a separate slice; user wants small phases. |
| Task 7 Step 1/3 Stop-mid-stream live probe on a second message (token freeze) | Deferred | Lifecycle headless suites and the earlier app's live Stop probe are green, but this route's live Stop-side-effect probe needs a disposable shell-capable OpenCode job and `/api/experimental/job`, `/api/shell`, PTY status records. |
| Tier 2 effective permissions and powerful-HTTP-route coverage | Deferred | Requires a real OpenCode harness instance with the controlled capability profile applied; cannot be proven from Sloppy source alone. |
| OpenCode runtime compatibility and send path | Not implemented end to end | The 2.3.2 contract helper is tested with synthetic observations but is not called by the app. The UI send path supplies neither live provider-endpoint observation nor permission evidence, so the route planner denies OpenCode sends. A disposable-service compatibility probe and runtime preflight are required. |
| Provider locality shown in the badge | Not verified | `Start-Stream` supplies no observed provider endpoint. The route planner consequently labels OpenCode remote even when the configuration preference says local. Display “Unverified” until the provider endpoint is observed and tied to the selected model. |
| Full Customize editing and persistence | Not implemented | The destination is read-only; the tray personality wizard discards its result. Add a save path that persists config/persona and refreshes the live UI. |
| Task 13 paid-provider connect | User-owned | Needs the user's provider account connected through OpenCode `/connect`. The onboarding wizard has no credential-entry fields; account connection remains in OpenCode. |
| Task 7 Step 4 memory measurement of the bundled model at 4k context (<4.5 GB) | Not run | The approved target `Qwen3-4B-GGUF` is not present on this machine. The only local models are 9B/other GGUFs, whose peak RSS cannot validate the 4B budget. Do not report a pass from a stand-in. |
| Task 7 Step 5 clean-Windows-VM installer checks | User-owned | No clean VM and no signing certificate in this environment. Checklist below. |
| Public repo creation, first push | User-owned | Six older commits in the working repo contain personal repository paths. The user creates the GitHub repo/remote and makes the first commit from a history-free snapshot. |

## 3. User-owned clean-VM installer checklist (do not mark complete without results)

1. Double-click the signed `.exe`; no UAC prompt; install finishes.
2. Start menu entry launches Sloppy; onboarding appears on first run.
3. Autostart toggle in tray survives a sign-out.
4. Tray Sleep model frees the model process; next message wakes it (this exercises the new worker-start handoff).
5. Uninstall removes both `Programs\Sloppy` and `%LOCALAPPDATA%\Sloppy`.
6. One-line bootstrap downloads the same `.exe` and the hash matches.

## 4. Release gate status

- The report records green headless, verify, geometry, tour and bundled-local live chat/destination/
  window/motion results. These were not rerun during the review. They do **not** establish an OpenCode
  send path, runtime compatibility gate, true OpenCode locality, or editable Customize flow.
- The existing `main` checkout is unsafe to push because its history contains personal paths and
  another person's identity references, and its staged tree includes private `.memory` and `.opencode` files. Use only the
  separately audited, history-free candidate for public publication.
- Release to public: **blocked** on user-owned repo/remote, signing certificate, clean-VM results,
  target-model memory measurement, and the deferred live onboarding/Stop probes.
- No commit, push, deploy or CI/CD change was made during the review. Phase 1 and partial Phase 2 files
  remain staged for the user to review and commit; the report correction itself is an unstaged edit.
