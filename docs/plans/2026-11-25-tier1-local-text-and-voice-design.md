# Tier 1 local text and voice design

Approved through brainstorming on 2026-11-25. This public repository deliberately ignores `docs/superpowers/`, so the design lives here instead of the default skill path.

## 1. Goal

Make Tier 1 a complete offline local companion:

- the bundled Gemma 4 E2B QAT Q4_0 model answers text messages through the existing llama.cpp path;
- the user can speak instead of typing by pressing the Mic button once to start and pressing it again to stop;
- recorded audio is transcribed locally by bundled Whisper small, then sent through the **same text send path** as a typed message;
- first-run checks, config, onboarding, Settings, docs, and tests ship with the feature.

No network call, account, API key, or Tier 2/OpenCode change is required for Tier 1.

## 2. Decisions already made

| Decision | Choice |
|---|---|
| Audio meaning | Voice in, text out. No spoken replies. |
| Transcription engine | Bundled `whisper.cpp` CLI, `ggml-small.bin` multilingual model. |
| Mic interaction | Toggle: press to start recording, press again to stop, transcribe, and send. No voice-activity auto-stop. |
| Transcription host | Headless `Slop.Audio.ps1` invoking `whisper-cli` per utterance. No daemon, no port. |
| Voice default | Disabled. User opts in from onboarding or Settings. |
| Transcript handling | Auto-send through `Start-Stream -UserText` on successful stop. |
| Safety cap | Recording hard-stops at `voiceMaxSeconds` (default 30). This is a runaway guard, not VAD. |
| mmproj | Keep as an unused readiness hook. Tier 1 makes no image claim. |

## 3. Scope

In scope:

- `src/Slop.Audio.ps1` — new headless transcription module.
- `src/Slop.ps1` — replace the Mic branch's current WAV-attachment behavior with toggle-to-transcribe-and-send.
- `src/Slop.Config.ps1` — config version 1 to 2 migration, validation, and new voice keys.
- `src/Slop.Onboarding.ps1` — voice controls on existing Screen 4; wizard stays four screens.
- Settings panel in `src/Slop.ps1` — matching voice controls and a readiness/repair action.
- `tools/slop-preflight.ps1` — headless readiness report for llama, Gemma, Whisper CLI, and Whisper model.
- `.gitattributes` — LFS rules for the Whisper runtime and `*.bin`.
- Tests, docs, and third-party notices described below.

Out of scope:

- TTS / spoken replies.
- Raw audio sent directly to Gemma.
- Image capture or image attachments.
- Tier 2/OpenCode route changes.
- Signed installer, CI, release artifacts, and publish/push actions.
- Claiming Tier 1 done without a real mic + real Whisper live smoke.

## 4. Architecture and components

### 4.1 `src/Slop.Audio.ps1`

Headless module. No WPF, no network, no registry.

Functions:

- `Get-SlopWhisperPaths -InstallRoot -CliFile -ModelFile`
  Returns resolved absolute paths for `whisper-cli.exe` and `ggml-small.bin`. Paths in config are relative to the install root; absolute paths are accepted for tests and overrides.
- `Test-SlopWhisperReady -Paths`
  Returns `@{ Ok = [bool]; Errors = [string[]] }`. Checks file existence and that the CLI path is an executable file.
- `Test-SlopWhisperIntegrity -Paths`
  Computes SHA-1 of the model and compares it with the pinned value in section 6. Used by preflight, not on every startup.
- `Convert-SlopWhisperOutput -Raw`
  Trims each line, drops empty lines, joins the remaining lines with a single space, and returns one transcript string.
- `Invoke-SlopWhisperTranscription -Paths -WavPath -Language -TimeoutSeconds`
  Runs the CLI and returns `@{ Ok; Text; Reason; ExitCode }`. The command shape is:

  ```powershell
  & $Paths.Cli -m $Paths.Model -f $WavPath -l $Language -nt -np -t 4
  ```

  `-nt` suppresses timestamps and `-np` suppresses output other than results. Only stdout is treated as transcript text; stderr is captured separately for error reporting. The WAV file is never modified.

### 4.2 `src/Slop.ps1`

The Mic button already toggles WinMM recording. Change only the stop branch:

1. Stop, save, and close the `slopmic` recording.
2. Validate that the WAV exists and is non-empty.
3. Dispatch a one-shot `Start-ThreadJob` that calls `Invoke-SlopWhisperTranscription`. This keeps native CLI latency off the WPF dispatcher. No model is kept resident between utterances.
4. Enqueue `__VOICE__<transcript>` or `__VOICEERR__<reason>` on the existing dispatcher queue.
5. On success, show the transcript as a user bubble and call `Start-Stream -UserText $text -Attachments @()`.
6. Delete the temp WAV in `finally`.
7. Disable Mic and Send while transcribing; re-enable on completion or error.

The current `New-SlopAttachmentFromFile` call in the Mic branch is removed. File attachment via the Attach button stays unchanged.

### 4.3 Transport and route boundaries

Tier 1 uses the existing `local-bundled` route. `Get-SlopRoutePlan`, `Slop.Adapter.OpenAi.ps1`, and `Slop.LocalModel.ps1` are unchanged. Voice is an input method, not a new route kind.

## 5. Data flow

```text
Mic press 1 -> WinMM starts WAV recording -> button shows stop state
Mic press 2 -> WAV saved -> one-shot ThreadJob runs whisper-cli -> transcript queued
dispatcher -> user bubble -> Start-Stream -UserText <transcript> -> existing llama-server adapter
```

If `voiceEnabled` is false, the Mic button shows `Enable voice input in Settings` and does not record.

## 6. Bundled Whisper artifacts

| Artifact | Relative path | Expected size | Integrity |
|---|---|---:|---|
| CLI | `runtime\whisper\whisper-cli.exe` | build-dependent | file existence + execute check |
| Model | `runtime\whisper\models\ggml-small.bin` | 466 MiB | SHA-1 `55356645c2b361a969dfd0ef2c5a50d530afd8d5` |

The model filename and SHA come from the official `ggml-org/whisper.cpp` model table. The CLI flag names come from the current `whisper-cli` help output. `docs/third-party-notices.md` must record the `whisper.cpp` MIT license, the pinned model filename, and its SHA-1; release-time license review remains a separate gate.

## 7. Config version 2

Add these keys to `New-SlopDefaultConfig`:

| Key | Default | Validation |
|---|---|---|
| `version` | `2` | `Read-SlopConfig` migrates version 1 to 2 before validation |
| `voiceEnabled` | `$false` | boolean |
| `whisperRuntimeFile` | `runtime\whisper\whisper-cli.exe` | non-empty, at most 260 chars |
| `whisperModelFile` | `runtime\whisper\models\ggml-small.bin` | non-empty, at most 260 chars |
| `whisperLanguage` | `auto` | `auto` or a lowercase 2-3 letter language code |
| `voiceMaxSeconds` | `30` | integer 10-120 |

Migration rules:

- Missing new keys take defaults.
- Invalid enum/boolean/range values normalize to defaults instead of failing the whole config.
- Existing keys and values are preserved.
- `Write-SlopConfig` keeps the existing `.bak` behavior and atomic temp-file move.

## 8. UI, onboarding, and settings

### 8.1 Onboarding Screen 4

Keep the existing four-screen wizard. Add a compact “Voice input” group:

- checkbox: `Enable voice input` (unchecked by default);
- combo: language (`auto`, `en`, and other supported codes);
- text: Whisper readiness (`Ready`, or the exact missing artifact).

### 8.2 Settings panel

Add:

- `Voice enabled` checkbox;
- `Language` combo;
- `Max seconds` numeric field;
- `Repair voice` button that reruns `tools/slop-preflight.ps1` in report-only mode and shows the result in a thought bubble.

`Save-SlopSettings` validates through the version 2 schema and reports config errors in the existing thought-bubble path.

## 9. Preflight and scaffolding

`tools/slop-preflight.ps1` is headless and parameterizable with `-InstallRoot`. It reports, per component:

- llama server executable present;
- Gemma model file present;
- Whisper CLI present;
- Whisper model present and SHA-1 matches;
- config version and voice settings valid.

It writes a human-readable report and returns a nonzero exit code for missing or integrity-failed required Tier 1 artifacts. It never downloads anything and never modifies user config.

`.gitattributes` gains `runtime/whisper/** filter=lfs` and `*.bin filter=lfs`.

## 10. Error handling

| Condition | Behavior |
|---|---|
| Voice disabled | Mic tooltip points to Settings; no recording starts |
| Whisper CLI missing | Thought bubble names `whisperRuntimeFile`; no send |
| Whisper model missing or wrong SHA | Thought bubble names `whisperModelFile`; no send |
| WinMM record failure | Existing catch closes `slopmic`, resets button, shows error bubble |
| Empty or whitespace transcript | “I didn't catch that.” No send |
| CLI nonzero exit or timeout | Thought bubble includes exit code/reason; no send |
| Any completion path | Temp WAV deleted; Mic/Send re-enabled |

Audio data and transcripts are not written to logs or to disk beyond the temporary recording, which is deleted.

## 11. Tests

New `tests/slop-audio-check.ps1` covers:

- path resolution with relative and absolute overrides;
- readiness success and each missing-file failure;
- output parsing with timestamps, blank lines, and plain text;
- version 1 to version 2 migration with missing and invalid keys;
- config rejection for out-of-range `voiceMaxSeconds` and malformed language;
- `Invoke-SlopWhisperTranscription` against a fake CLI stand-in that emits known text.

New `tests/slop-preflight-check.ps1` uses a disposable install root with stub artifacts and verifies the report and exit code.

Existing `tests/slop-shell-check.ps1` gains assertions that:

- the Mic stop branch calls `Invoke-SlopWhisperTranscription` and `Start-Stream`;
- the Mic stop branch does not call `New-SlopAttachmentFromFile`;
- Settings saves the new voice keys.

After source edits, refresh CodeTour anchors and inline line references, then run canonical verify, tour check, review, and `git diff --check`.

## 12. Acceptance criteria

Tier 1 is done when all of the following are true:

1. A version 1 config migrates to version 2 without losing existing values.
2. Voice is disabled on a clean install and opt-in persists across restart.
3. Pressing Mic once starts recording; pressing again transcribes locally and sends the transcript as a normal text message.
4. No audio or transcript leaves the machine, and no Tier 2 route is touched.
5. Preflight correctly reports ready and unready states using a disposable install root.
6. All headless gates are green: canonical verify, audio tests, preflight tests, tour anchors, review, and diff check.
7. A real mic + real Whisper small live smoke confirms the full toggle path. If the environment cannot provide this, it is reported as deferred and Tier 1 is not called done.

## 13. Risks and trade-offs

- **Per-utterance CLI startup:** accepted for the first Tier 1 cut. A persistent worker is the deliberate upgrade path if live latency is unacceptable.
- **WinMM capture quality:** the existing recorder is reused instead of adding a new audio stack. It records WAV, which `whisper-cli` supports directly.
- **500 MB model bundle:** accepted by the user for better accuracy. LFS rules and integrity checking mitigate corrupt or missing artifacts.
- **Line shifts:** `Slop.ps1`, `Slop.Config.ps1`, and `Slop.Onboarding.ps1` have anchored docs and shell checks; anchors must be refreshed in the same pass as source edits.
- **Live verification:** headless tests with a fake CLI do not prove mic capture or model behavior. The real live smoke remains a hard gate.

## 14. Reference

- `whisper.cpp` CLI options: https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md
- Official ggml model table and SHA values: https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- Existing Tier 1 route: `src/Slop.Route.ps1`, `src/Slop.LocalModel.ps1`, `src/Slop.Adapter.OpenAi.ps1`
- Existing first-run plan: `docs/bundling-and-first-run-plan.md`
