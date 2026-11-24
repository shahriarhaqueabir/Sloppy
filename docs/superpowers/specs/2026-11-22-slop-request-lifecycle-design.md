# S.L.O.P. Request Lifecycle Design

Status: approved on 2026-11-22 by the user.
Goal: make the full request lifecycle explicit and robust, including connection,
first token, streaming, completion, and every failure path, without changing how
Slop looks or moves.

## Context

Slop currently streams from an OpenAI-compatible llama.cpp endpoint. The request
logic is embedded in `src/Slop.ps1` alongside WPF markup and UI handlers. It works
on the happy path but has seven confirmed defects:

1. Time-to-first-token and inter-token delay are not distinguished in state.
2. `StreamReader` and `HttpClient` are disposed only on the success path; cancel,
   HTTP error, timeout, and connection failure all leak them.
3. There is no generation guard, so a late event from a cancelled request can land
   in the next request's timer window and overwrite the wrong chat bubble.
4. A 5-minute `HttpClient.Timeout` throws `TaskCanceledException`, which is caught
   as `OperationCanceledException` and mislabelled `[cancelled]`.
5. Malformed SSE events are swallowed by an empty `catch { }`.
6. An empty response finalizes silently with no label.
7. On error, accumulated partial text is replaced by the error label.

## Scope

In scope: a pure lifecycle module, its wiring into the existing WPF app, and
headless tests.

Out of scope: the OpenCode bridge (sub-project B), the character restyle,
stall-slows motion, changes to the signal table, and changes to any shape, color,
size, or animation.

## Architecture

One new file, following the existing `Slop.Motion.ps1` precedent:

```
src/Slop.Motion.ps1      pure spring/signal math (unchanged)
src/Slop.Lifecycle.ps1   NEW: pure request lifecycle, no WPF, no I/O beyond a TextReader
src/Slop.ps1             imports both; owns only WPF wiring and UI state
```

`Slop.ps1` cannot be imported by a headless test because loading it constructs a
WPF window. The lifecycle module must remain importable on its own so the test
script can drive it directly.

## State model

`New-SlopRequestState` returns a hashtable:

| Field | Meaning |
|---|---|
| `Generation` | Integer, incremented by each accepted `Start-SlopRequest`. |
| `Phase` | `idle`, `initiated`, `connected`, `streaming`, `completed`, `failed`, `finalized`. |
| `StartedAt` | Request creation time. |
| `ConnectedAt` | Response headers received. |
| `FirstTokenAt` | First content delta received. |
| `LastTokenAt` | Most recent content delta. |
| `CompletedAt` | Stream ended with `[DONE]`. |
| `FinalizedAt` | UI cleanup finished. |
| `FailureReason` | `Cancelled`, `Timeout`, `HTTP <code>`, or other message. |
| `MalformedCount` | SSE lines that failed JSON parsing. |
| `TokenCount` | Content deltas accepted. |
| `LastInterTokenGap` | Gap between the two most recent tokens. |

Phases advance in one direction per request:
`idle → initiated → connected → streaming → completed → finalized`, with `failed`
reached from any active phase. `cancelled` is a failure reason, not a phase.

## Public API

All functions are pure with respect to the outside world except
`Read-SlopSseStream`, which reads a supplied `TextReader` and writes to a supplied
concurrent queue.

| Function | Result |
|---|---|
| `New-SlopRequestState` | Fresh idle state at generation 0. |
| `Start-SlopRequest -State -Now` | `true` if accepted; bumps generation, sets `initiated`. Rejects when a phase is active. |
| `Set-SlopRequestConnected -State -Generation -Now` | `true` if current; sets `connected`. |
| `Set-SlopRequestFirstToken -State -Generation -Now` | `true` if current; sets `streaming`, records `FirstTokenAt`. |
| `Set-SlopRequestToken -State -Generation -Now` | `true` if current; updates last token and inter-token gap. |
| `Set-SlopRequestCompleted -State -Generation -Now` | `true` if current; sets `completed`. |
| `Set-SlopRequestFailed -State -Generation -Reason -Now` | `true` if current; sets `failed`. |
| `Set-SlopRequestFinalized -State -Generation -Now` | `true` if current; sets `finalized`. |
| `Test-SlopRequestGeneration -State -Generation` | `true` only when generation matches and phase is active. |
| `Get-SlopRequestTiming -State -Now` | `Ttft`, `InterTokenGap`, `SinceLastToken`, `Elapsed`. |
| `Read-SlopSseStream -Reader -Queue` | Enqueues content deltas; returns `Malformed` and `Tokens` counts. Stops at `[DONE]`. |
| `Resolve-SlopStreamToken -Token` | Classifies as `done`, `cancelled`, `timeout`, `http`, `error`, or `token`. |
| `Format-SlopStreamFailure -PartialText -Kind -Reason` | Label appended to preserved partial text. |
| `Format-SlopEmptyResponse -Text` | `[empty response]` when blank, otherwise `$null`. |

Timing definitions:

- `Ttft` = `FirstTokenAt - StartedAt`, `$null` before the first token.
- `InterTokenGap` = most recent completed gap between consecutive tokens,
  `$null` before the second token.
- `SinceLastToken` = `Now - LastTokenAt`, informational only.
- `Elapsed` = `Now - StartedAt`.

Every state mutator other than `Start-SlopRequest` returns `false` and does
nothing when `Generation` does not match. This is the late-event guard.
`Start-SlopRequest` is the only function that increments the generation, and it
rejects any call made while a phase is active.

## Wiring

`Start-Stream` in `Slop.ps1`:

1. Calls `Start-SlopRequest` and captures the returned generation.
2. Passes that generation into both the `Start-ThreadJob` scriptblock and the
   dispatcher timer closure.
3. The thread job calls `Set-SlopRequestConnected` after `SendAsync` returns
   headers, then uses `Read-SlopSseStream` to parse the body.
4. The timer drops any dequeued event whose generation is no longer current.

The Stop button calls `Cts.Cancel()` as it does today. It also records the
cancelled phase through `Set-SlopRequestFailed`.

`Finish-Stream` calls `Set-SlopRequestFinalized` and runs only for the current
generation.

## Error handling

| Path | Detection | Result |
|---|---|---|
| Connection failure | Exception from `SendAsync` | `[error: <message>]` |
| HTTP error | Non-success `StatusCode` | `[error: HTTP <code>]` |
| Timeout | `TaskCanceledException` with `Cts.IsCancellationRequested` false | `[timeout after Ns]` |
| Cancellation | `OperationCanceledException` with cancellation requested | `[cancelled]` |
| Malformed SSE | JSON parse failure counted by `Read-SlopSseStream` | If zero tokens: `[error: Malformed stream (n event(s))]`. If partial text exists: append `[n malformed event(s)]`. |
| Empty response | `__DONE__` with no failure and blank text | `[empty response]` |
| Partial + interruption | Failure after tokens arrived | Partial text preserved; label appended on a new line. |

`Read-SlopSseStream`, `HttpClient`, response, and stream are declared before the
`try` block and disposed unconditionally in `finally`. `__DONE__` is enqueued in
`finally` so the UI always returns to a stable state.

Timeout is read from `SLOP_REQUEST_TIMEOUT_SECONDS`, default `300`.

## Visual invariance

The signal table, shapes, colors, sizes, springs, and live verifier are unchanged.
TTFT and inter-token gap are recorded internally but the existing stall rule stays
as-is: `IsStreaming` and more than 3 seconds since request start set the amber
rectangle. No new visual state is introduced.

## Verification

- `tests/slop-lifecycle-check.ps1`: headless tests for every phase transition,
  generation rejection, timing definitions, SSE parsing, classification, and
  formatting. This file already exists and currently fails with
  `missing lifecycle functions`, which is the RED gate.
- `tests/slop-motion-check.ps1`: unchanged, must stay green.
- `tools/verify-motion.ps1`: live WPF verifier, unchanged, must stay green.
- Verify and review gates after implementation.

## Risks

- The generation guard must be checked at both enqueue and dequeue boundaries;
  checking only one leaves a race where a cancelled job's `__DONE__` can still
  finalize a new request.
- PowerShell `catch` ordering matters: `TaskCanceledException` derives from
  `OperationCanceledException`, so it must be caught first.
- Moving disposal into `finally` must be null-safe because construction itself can
  fail.
