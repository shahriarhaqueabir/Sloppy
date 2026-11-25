# Tier 1 local text and voice — implementation plan

Status: ready to execute. Source of truth: `docs/plans/2026-11-25-tier1-local-text-and-voice-design.md` (approved 2026-11-25). This public repo ignores `docs/superpowers/`, so both design and plan live in `docs/plans/`.

This plan writes **no Tier 1 source code**. It is the execution script for the approved design: every task is RED → GREEN, uses explicit paths, and ends with named gates. Do not push, deploy, touch release-readiness files, edit Tier 2 routes, or add TTS/VAD/image UX.

## Baseline

- Branch: `feat/gemma4-e2b-tier1`.
- HEAD at recon: `052aad5587d11e801a52501ea277a8bf660be6ef`.
- Baseline gates after the spec commit: canonical verify `543/543`, tour `38/38`, review exit `0`, tree clean.
- Public branch is unpublished (`origin/main` is `0cffd5d7c6243cc028ff48b693295fc2cd45e014`, `1 21` behind/ahead); no push is authorized.

Canonical commands used throughout (run from the repo root):

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path . -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-tour-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\review.ps1" -ProjectPath (Get-Location).Path
git diff --check
```

Use `tests/Slop.Tests.ps1` discovery (the canonical verify gate runs it). Never trust `Invoke-Pester -Path .\tests -Output None` alone: a container discovery failure can hide later suites.

## Validation performed before writing this plan

Risky snippets were copied into `C:\Users\shahr\AppData\Local\Temp\opencode\tier1-probe\` and executed. Results:

| Probe | Result |
|---|---|
| Fake `whisper-cli.cmd` through `Invoke-SlopWhisperTranscription` | `Ok=true`, `Text="hello from whisper second line"`, temp stdout/stderr removed |
| Timestamp/blank-line parser | `"[00:00:00.000 --> 00:00:01.000] hello\r\n\r\n  world  "` → `"hello world"` |
| Config v2 migration/normalization | v1 with `voiceMaxSeconds:45` → v2 keeps `45`; malformed `whisperLanguage:"EN"`, `voiceMaxSeconds:2`, `voiceEnabled:"yes"` → `auto`, `30`, `$false` |
| Config validation | `-cnotmatch` catches uppercase language; `voiceMaxSeconds=9` rejected |
| Preflight with stub artifacts | ready report `Ok=true`; removing `whisper-cli.exe` gives exactly one error and `Ok=false` |
| PowerShell parser on every source snippet below | `parse-errors=0` |
| Settings and onboarding XAML fragments | both parsed and all `FindName` targets found |
| Tour anchor refresh script | all 17 anchored steps resolved by text fragment |

Two probe defects were found and fixed in the snippets below: PowerShell `else $value` is invalid (must be `else { $value }`), and `-match` is case-insensitive so language validation must use `-cnotmatch`.

Design refinement, called out honestly: the design says voice events go on "the existing dispatcher queue". That queue is created **inside** `Start-Stream`, is generation-scoped, and its tick early-returns unless a request is active. Voice therefore uses a dedicated script-scoped `$script:VoiceQueue` and `$script:VoiceTimer` modeled on the same marker pattern. This is required for voice to work when no chat is streaming; it does not change any route or adapter.

## Task 0 — baseline proof (no edits)

```powershell
git status --short --branch
git rev-parse HEAD
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-tour-check.ps1 -PassThru | Out-Null"
```

Expected: clean tree at `052aad5`, verify `All gates passed.` (543 tests), tour exit `0`. If not, stop and report; do not stack Tier 1 work on a red baseline.

---

## Task 1 — config version 2 (RED → GREEN)

Files: `tests/slop-config-check.ps1`, `src/Slop.Config.ps1`.

### 1a. RED tests

Replace the existing `migrates version 0 to version 1 in memory` block at `tests/slop-config-check.ps1:163-168` with this block, and append the three new blocks before the closing `}` of the `Describe`:

```powershell
    It 'migrates version 0 and version 1 configs to version 2 in memory' {
        foreach ($version in 0, 1) {
            [IO.File]::WriteAllText($script:ConfigPath, ('{"version":{0},"name":"Pea"}' -f $version), [Text.UTF8Encoding]::new($false))
            $r = Read-SlopConfig -ConfigPath $script:ConfigPath
            $r.Ok | Should -BeTrue
            $r.Config.version | Should -Be 2
            $r.Config.name | Should -Be 'Pea'
        }
    }

    It 'defaults voice off with pinned Whisper relative paths' {
        $cfg = New-SlopDefaultConfig
        $cfg.version | Should -Be 2
        $cfg.voiceEnabled | Should -BeFalse
        $cfg.whisperRuntimeFile | Should -Be 'runtime\whisper\whisper-cli.exe'
        $cfg.whisperModelFile | Should -Be 'runtime\whisper\models\ggml-small.bin'
        $cfg.whisperLanguage | Should -Be 'auto'
        $cfg.voiceMaxSeconds | Should -Be 30
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }

    It 'normalizes malformed voice values to safe defaults and preserves valid ones' {
        [IO.File]::WriteAllText($script:ConfigPath, '{"version":2,"voiceEnabled":true,"whisperLanguage":"EN","whisperModelFile":"","voiceMaxSeconds":2}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.voiceEnabled | Should -BeTrue
        $r.Config.whisperLanguage | Should -Be 'auto'
        $r.Config.whisperModelFile | Should -Be 'runtime\whisper\models\ggml-small.bin'
        $r.Config.voiceMaxSeconds | Should -Be 30

        [IO.File]::WriteAllText($script:ConfigPath, '{"version":2,"voiceEnabled":true,"voiceMaxSeconds":45}', [Text.UTF8Encoding]::new($false))
        $r2 = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r2.Ok | Should -BeTrue
        $r2.Config.voiceMaxSeconds | Should -Be 45
    }

    It 'rejects out-of-range voice settings in Test-SlopConfig' {
        $badLanguage = New-SlopDefaultConfig
        $badLanguage.whisperLanguage = 'EN'
        ((Test-SlopConfig -Config $badLanguage).Errors -join '; ') | Should -Match 'whisperLanguage'

        $badSeconds = New-SlopDefaultConfig
        $badSeconds.voiceMaxSeconds = 9
        ((Test-SlopConfig -Config $badSeconds).Errors -join '; ') | Should -Match 'voiceMaxSeconds'

        $badBool = New-SlopDefaultConfig
        $badBool.voiceEnabled = 'yes'
        ((Test-SlopConfig -Config $badBool).Errors -join '; ') | Should -Match 'voiceEnabled'
    }
```

Run RED:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-config-check.ps1 -PassThru | Out-Null"
git add tests/slop-config-check.ps1
git commit -m "test(config): red Tier 1 voice config v2"
```

Expected: at least four failures (version still 1, missing keys, no validation).

### 1b. GREEN source

In `src/Slop.Config.ps1`, change line 4:

```powershell
$script:SlopConfigVersion = 2
```

Replace the bundled-brain comment and add the new keys in `New-SlopDefaultConfig` (replacing lines 64-71):

```powershell
        # Tier 1 bundled local brain (Gemma 4 E2B QAT Q4_0). localVisionReady and
        # localAudioReady remain readiness hooks; Tier 1 voice uses the explicit
        # Slop.Audio.ps1 paths below, not a capability flag.
        localModelName    = 'Gemma 4 E2B QAT Q4_0'
        localModelFile    = 'models\gemma-4-E2B_q4_0-it.gguf'
        localMmprojFile   = 'models\gemma-4-E2B-it-mmproj.gguf'
        localContextSize  = 8192
        localVisionReady  = $true
        localAudioReady   = $true

        # Tier 1 voice input. Voice is opt-in and stays inside this machine.
        voiceEnabled      = $false
        whisperRuntimeFile = 'runtime\whisper\whisper-cli.exe'
        whisperModelFile   = 'runtime\whisper\models\ggml-small.bin'
        whisperLanguage    = 'auto'
        voiceMaxSeconds    = 30
```

Insert into `Test-SlopConfig` immediately after the `localAudioReady` check:

```powershell
    if ($Config.voiceEnabled -isnot [bool]) { $errors.Add('voiceEnabled must be a boolean') }
    if ([string]::IsNullOrWhiteSpace([string]$Config.whisperRuntimeFile) -or ([string]$Config.whisperRuntimeFile).Length -gt 260) {
        $errors.Add('whisperRuntimeFile must be 1-260 characters')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config.whisperModelFile) -or ([string]$Config.whisperModelFile).Length -gt 260) {
        $errors.Add('whisperModelFile must be 1-260 characters')
    }
    if ([string]$Config.whisperLanguage -cnotmatch '^(auto|[a-z]{2,3})$') {
        $errors.Add('whisperLanguage must be auto or a lowercase 2-3 letter code')
    }
    if ($Config.voiceMaxSeconds -isnot [int] -or [int]$Config.voiceMaxSeconds -lt 10 -or [int]$Config.voiceMaxSeconds -gt 120) {
        $errors.Add('voiceMaxSeconds must be an integer between 10 and 120')
    }
```

`-cnotmatch` is deliberate: `-match` would accept `EN` and silently break the official Whisper language flag.

Replace the version migration lines and comment in `Read-SlopConfig` (old lines 155-156 and 161), and insert the voice normalization block after the `localMmprojFile` normalization:

```powershell
    # Unknown keys are ignored. Missing known keys take defaults. Pre-voice
    # configs (version 0/1/absent) migrate to version 2 before validation.
```

```powershell
    # Version 0/1 configs are pre-voice shapes. Normalize numeric JSON values to
    # [int] before validation because ConvertFrom-Json emits [long].
    if ($cfg.version -is [int] -or $cfg.version -is [long]) { $cfg.version = [int]$cfg.version }
    else { $cfg.version = 2 }
    if ($cfg.version -lt 2) { $cfg.version = 2 }
```

```powershell
    # Voice keys are new in version 2. Existing values win; malformed values fall
    # back to the safe default rather than locking the user out of the app.
    if ($cfg.voiceEnabled -isnot [bool]) { $cfg.voiceEnabled = $defaults.voiceEnabled }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.whisperRuntimeFile)) { $cfg.whisperRuntimeFile = $defaults.whisperRuntimeFile }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.whisperModelFile)) { $cfg.whisperModelFile = $defaults.whisperModelFile }
    if ([string]$cfg.whisperLanguage -cnotmatch '^(auto|[a-z]{2,3})$') { $cfg.whisperLanguage = $defaults.whisperLanguage }
    if ($cfg.voiceMaxSeconds -is [int] -or $cfg.voiceMaxSeconds -is [long]) {
        $cfg.voiceMaxSeconds = [int]$cfg.voiceMaxSeconds
    }
    else { $cfg.voiceMaxSeconds = 30 }
    if ($cfg.voiceMaxSeconds -lt 10 -or $cfg.voiceMaxSeconds -gt 120) { $cfg.voiceMaxSeconds = 30 }
```

Run GREEN and commit explicit paths:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-config-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add src/Slop.Config.ps1 tests/slop-config-check.ps1
git commit -m "feat(config): version 2 Tier 1 voice schema and migration"
git diff --check
```

Expected: config suite green; canonical verify stays green (version assertion count may change, total rises by 3).

---

## Task 2 — headless Whisper module (RED → GREEN)

Files: `tests/slop-audio-check.ps1` (new), `src/Slop.Audio.ps1` (new).

### 2a. RED tests

```powershell
#requires -Version 7.6
Describe 'Slop.Audio' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')
    }

    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('slop-audio-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\whisper\models') -Force | Out-Null
        $script:Cli = Join-Path $script:Root 'runtime\whisper\whisper-cli.cmd'
        Set-Content -LiteralPath $script:Cli -Value @'
@echo off
echo [00:00:00.000 --^> 00:00:01.000] hello from whisper
echo.
echo second line
'@ -Encoding ascii
        $script:Model = Join-Path $script:Root 'runtime\whisper\models\ggml-small.bin'
        [IO.File]::WriteAllBytes($script:Model, [byte[]](1,2,3,4))
        $script:Wav = Join-Path $script:Root 'utterance.wav'
        [IO.File]::WriteAllBytes($script:Wav, [byte[]](1,2,3,4,5,6,7,8))
        $script:Paths = Get-SlopWhisperPaths -InstallRoot $script:Root `
            -CliFile 'runtime\whisper\whisper-cli.cmd' `
            -ModelFile 'runtime\whisper\models\ggml-small.bin'
    }

    AfterEach {
        Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'resolves relative and absolute paths without normalizing the user config' {
        $script:Paths.Cli | Should -Be (Join-Path $script:Root 'runtime\whisper\whisper-cli.cmd')
        $script:Paths.Model | Should -Be $script:Model
        $absolute = Get-SlopWhisperPaths -InstallRoot $script:Root -CliFile $script:Cli -ModelFile $script:Model
        $absolute.Cli | Should -Be $script:Cli
    }

    It 'reports readiness and names each missing artifact' {
        (Test-SlopWhisperReady -Paths $script:Paths).Ok | Should -BeTrue
        Remove-Item -LiteralPath $script:Cli -Force
        $missingCli = Test-SlopWhisperReady -Paths $script:Paths
        $missingCli.Ok | Should -BeFalse
        ($missingCli.Errors -join '; ') | Should -Match 'whisperRuntimeFile'
    }

    It 'parses timestamps, blank lines and plain text into one transcript' {
        Convert-SlopWhisperOutput -Raw "[00:00:00.000 --> 00:00:01.000] hello`r`n`r`n  world  " | Should -Be 'hello world'
        Convert-SlopWhisperOutput -Raw 'plain text' | Should -Be 'plain text'
        Convert-SlopWhisperOutput -Raw '' | Should -Be ''
    }

    It 'transcribes through a fake whisper-cli stand-in' {
        $result = Invoke-SlopWhisperTranscription -Paths $script:Paths -WavPath $script:Wav -Language 'en' -TimeoutSeconds 10
        $result.Ok | Should -BeTrue
        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be 'hello from whisper second line'
    }

    It 'reports an integrity failure without throwing' {
        $hash = (Get-FileHash -LiteralPath $script:Model -Algorithm SHA1).Hash.ToLowerInvariant()
        (Test-SlopWhisperIntegrity -Paths $script:Paths -ExpectedSha1 $hash).Ok | Should -BeTrue
        $bad = Test-SlopWhisperIntegrity -Paths $script:Paths -ExpectedSha1 '0000000000000000000000000000000000000000'
        $bad.Ok | Should -BeFalse
        $bad.Reason | Should -Match 'SHA-1'
    }

    It 'exposes a deterministic install root and readiness text for UI tests' {
        $env:SLOP_TEST_INSTALL_ROOT = $script:Root
        Get-SlopVoiceInstallRoot | Should -Be $script:Root
        $cfg = @{
            whisperRuntimeFile = 'runtime\whisper\whisper-cli.cmd'
            whisperModelFile   = 'runtime\whisper\models\ggml-small.bin'
        }
        Get-SlopVoiceReadinessText -Config $cfg | Should -Be 'Ready'
        Remove-Item -LiteralPath $script:Model -Force
        Get-SlopVoiceReadinessText -Config $cfg | Should -Match 'whisperModelFile'
    }

    It 'offers a bounded language list including auto' {
        $langs = @(Get-SlopWhisperLanguages)
        $langs[0] | Should -Be 'auto'
        $langs | Should -Contain 'en'
        $langs | Should -Contain 'zh'
    }
}
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-audio-check.ps1 -PassThru | Out-Null"
git add tests/slop-audio-check.ps1
git commit -m "test(audio): red Whisper wrapper contracts"
```

Expected: RED because `src/Slop.Audio.ps1` does not exist.

### 2b. GREEN source — `src/Slop.Audio.ps1`

This is the probe-validated module. Copy it verbatim:

```powershell
# Bundled Whisper transcription helpers. Headless: no WPF, no network, no registry.
#requires -Version 7.6
$ErrorActionPreference = 'Stop'

$script:SlopWhisperModelSha1 = '55356645c2b361a969dfd0ef2c5a50d530afd8d5'
$script:SlopWhisperExecutableExtensions = @('.exe', '.cmd', '.bat')

function Get-SlopWhisperLanguages {
    return @('auto', 'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'zh')
}

function Get-SlopVoiceInstallRoot {
    # Mirror Slop.LocalModel.ps1: the installed app keeps runtime/ under
    # LOCALAPPDATA. Tests override it so they never touch the real install.
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_INSTALL_ROOT)) {
        return [IO.Path]::GetFullPath($env:SLOP_TEST_INSTALL_ROOT)
    }
    return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\Sloppy'))
}

function Get-SlopVoiceReadinessText {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$InstallRoot = (Get-SlopVoiceInstallRoot)
    )
    $paths = Get-SlopWhisperPaths -InstallRoot $InstallRoot `
        -CliFile ([string]$Config.whisperRuntimeFile) -ModelFile ([string]$Config.whisperModelFile)
    $ready = Test-SlopWhisperReady -Paths $paths
    if ($ready.Ok) { return 'Ready' }
    return ($ready.Errors -join '; ')
}

function Get-SlopWhisperPaths {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CliFile,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ModelFile
    )
    $cli = if ([IO.Path]::IsPathRooted($CliFile)) { $CliFile } else { Join-Path $InstallRoot $CliFile }
    $model = if ([IO.Path]::IsPathRooted($ModelFile)) { $ModelFile } else { Join-Path $InstallRoot $ModelFile }
    return @{
        Cli   = [IO.Path]::GetFullPath($cli)
        Model = [IO.Path]::GetFullPath($model)
    }
}

function Test-SlopWhisperReady {
    param([Parameter(Mandatory)][hashtable]$Paths)

    $errors = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace([string]$Paths.Cli)) {
        $errors.Add('whisperRuntimeFile is empty')
    }
    elseif (-not (Test-Path -LiteralPath $Paths.Cli -PathType Leaf)) {
        $errors.Add("whisperRuntimeFile is missing: $($Paths.Cli)")
    }
    else {
        $ext = [IO.Path]::GetExtension([string]$Paths.Cli)
        if ($script:SlopWhisperExecutableExtensions -notcontains $ext) {
            $errors.Add("whisperRuntimeFile must be an executable file: $($Paths.Cli)")
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Paths.Model)) {
        $errors.Add('whisperModelFile is empty')
    }
    elseif (-not (Test-Path -LiteralPath $Paths.Model -PathType Leaf)) {
        $errors.Add("whisperModelFile is missing: $($Paths.Model)")
    }

    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Test-SlopWhisperIntegrity {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [string]$ExpectedSha1 = $script:SlopWhisperModelSha1
    )
    if (-not (Test-Path -LiteralPath $Paths.Model -PathType Leaf)) {
        return @{ Ok = $false; Expected = $ExpectedSha1; Actual = $null; Reason = "whisperModelFile is missing: $($Paths.Model)" }
    }
    $actual = (Get-FileHash -LiteralPath $Paths.Model -Algorithm SHA1).Hash.ToLowerInvariant()
    $ok = ($actual -eq $ExpectedSha1.ToLowerInvariant())
    return @{
        Ok       = $ok
        Expected = $ExpectedSha1.ToLowerInvariant()
        Actual   = $actual
        Reason   = if ($ok) { '' } else { "whisperModelFile has the wrong SHA-1: $($Paths.Model)" }
    }
}

function Convert-SlopWhisperOutput {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)
    $lines = @(
        $Raw -split '\r?\n' |
            ForEach-Object { ($_ -replace '^\s*\[[^\]]+\]\s*', '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    return ($lines -join ' ')
}

function Invoke-SlopWhisperTranscription {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][string]$WavPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Language,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
    )

    $ready = Test-SlopWhisperReady -Paths $Paths
    if (-not $ready.Ok) {
        return @{ Ok = $false; Text = ''; Reason = ($ready.Errors -join '; '); ExitCode = $null }
    }

    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("slop-whisper-out-" + [guid]::NewGuid().ToString('N') + '.txt')
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("slop-whisper-err-" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $argList = @(
            '-m', ('"' + $Paths.Model + '"')
            '-f', ('"' + $WavPath + '"')
            '-l', $Language
            '-nt', '-np'
            '-t', '4'
        )
        $process = Start-Process -FilePath $Paths.Cli -ArgumentList $argList -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
            return @{ Ok = $false; Text = ''; Reason = "whisper-cli timed out after $TimeoutSeconds seconds"; ExitCode = $null }
        }
        $process.WaitForExit()
        $raw = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $text = Convert-SlopWhisperOutput -Raw $raw
        if ($process.ExitCode -ne 0) {
            $stderr = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw).Trim() } else { '' }
            $reason = if ($stderr) { "whisper-cli exited $($process.ExitCode): $stderr" } else { "whisper-cli exited $($process.ExitCode)" }
            return @{ Ok = $false; Text = ''; Reason = $reason; ExitCode = $process.ExitCode }
        }
        return @{ Ok = $true; Text = $text; Reason = ''; ExitCode = 0 }
    }
    catch {
        return @{ Ok = $false; Text = ''; Reason = $_.Exception.Message; ExitCode = $null }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}
```

`.cmd` and `.bat` are accepted as stand-ins so a fake CLI can be tested headlessly; shipped config still points at `whisper-cli.exe`. Only stdout is transcript; stderr is reported on failure. The WAV is never modified by this module.

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-audio-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add src/Slop.Audio.ps1 tests/slop-audio-check.ps1
git commit -m "feat(audio): headless local Whisper transcription module"
git diff --check
```

Expected: audio suite `8/8`; canonical verify stays green with 8 new tests.

---

## Task 3 — preflight reporter (RED → GREEN)

Files: `tests/slop-preflight-check.ps1` (new), `tools/slop-preflight.ps1` (new).

### 3a. RED tests

```powershell
#requires -Version 7.6
Describe 'Slop preflight' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')
        $script:Tool = Join-Path $PSScriptRoot '../tools/slop-preflight.ps1'
        . $script:Tool
    }

    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('slop-preflight-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\llama-b12676-bin-win-cuda-13.5-x64') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\whisper\models') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'models') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Root 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe') -Value 'stub' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $script:Root 'models\gemma-4-E2B_q4_0-it.gguf') -Value 'stub' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Value 'stub' -Encoding ascii
        $script:Model = Join-Path $script:Root 'runtime\whisper\models\ggml-small.bin'
        [IO.File]::WriteAllBytes($script:Model, [byte[]](1,2,3,4,5,6,7,8))
        $script:Hash = (Get-FileHash -LiteralPath $script:Model -Algorithm SHA1).Hash.ToLowerInvariant()
        $script:ConfigPath = Join-Path $script:Root 'config.json'
        Write-SlopConfig -Config (New-SlopDefaultConfig) -ConfigPath $script:ConfigPath
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'reports a fully stubbed Tier 1 install as ready' {
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash
        $report.Ok | Should -BeTrue
        @($report.Errors).Count | Should -Be 0
        ($report.Lines -join "`n") | Should -Match '\[OK\] config: config version 2'
        ($report.Lines -join "`n") | Should -Match '\[OK\] Whisper model SHA-1'
    }

    It 'names a missing Whisper CLI and fails closed' {
        Remove-Item -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Force
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash
        $report.Ok | Should -BeFalse
        ($report.Errors -join '; ') | Should -Match 'whisperRuntimeFile'
    }

    It 'reports a model hash mismatch' {
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 '0000000000000000000000000000000000000000'
        $report.Ok | Should -BeFalse
        ($report.Lines -join "`n") | Should -Match 'Whisper model SHA-1: expected'
    }

    It 'uses exit code 1 for a missing artifact and 0 with -ReportOnly' {
        Remove-Item -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Force
        & pwsh -NoProfile -File $script:Tool -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        & pwsh -NoProfile -File $script:Tool -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash -ReportOnly 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'never writes user config during a report' {
        $before = [IO.File]::ReadAllBytes($script:ConfigPath)
        Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash | Out-Null
        $after = [IO.File]::ReadAllBytes($script:ConfigPath)
        ($before -join ',') | Should -Be ($after -join ',')
    }
}
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-preflight-check.ps1 -PassThru | Out-Null"
git add tests/slop-preflight-check.ps1
git commit -m "test(preflight): red Tier 1 readiness report contracts"
```

### 3b. GREEN source — `tools/slop-preflight.ps1`

Probe-validated source:

```powershell
# Headless Tier 1 readiness report. Never downloads, never writes user config.
#requires -Version 7.6
param(
    [string]$InstallRoot,
    [string]$ConfigPath,
    [string]$ExpectedModelSha1,
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
. (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
. (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')

function Invoke-SlopPreflight {
    param(
        [string]$InstallRoot,
        [string]$ConfigPath,
        [string]$ExpectedModelSha1
    )
    $root = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { Get-SlopVoiceInstallRoot } else { [IO.Path]::GetFullPath($InstallRoot) }
    $cfgPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Get-SlopConfigPath } else { $ConfigPath }
    $lines = [Collections.Generic.List[string]]::new()
    $errors = [Collections.Generic.List[string]]::new()

    $configResult = Read-SlopConfig -ConfigPath $cfgPath
    if ($configResult.Ok) {
        $cfg = $configResult.Config
        $configText = if ($configResult.Exists) {
            "config version $($cfg.version), voiceEnabled=$($cfg.voiceEnabled), whisperLanguage=$($cfg.whisperLanguage), voiceMaxSeconds=$($cfg.voiceMaxSeconds)"
        }
        else {
            "config defaults (not written yet), version $($cfg.version), voiceEnabled=$($cfg.voiceEnabled)"
        }
        $lines.Add("[OK] config: $configText")
    }
    else {
        $errors.Add("config: $($configResult.Reason)")
        $lines.Add("[FAIL] config: $($configResult.Reason)")
        $cfg = New-SlopDefaultConfig
    }

    $modelPaths = Get-SlopRuntimePaths -InstallRoot $root -ModelFile ([string]$cfg.localModelFile) -MmprojFile ([string]$cfg.localMmprojFile)
    foreach ($entry in @(
        @{ Label = 'llama server'; Path = $modelPaths.ServerExe },
        @{ Label = 'Gemma model'; Path = $modelPaths.ModelFile }
    )) {
        if (Test-Path -LiteralPath $entry.Path -PathType Leaf) { $lines.Add("[OK] $($entry.Label): $($entry.Path)") }
        else {
            $errors.Add("$($entry.Label) is missing: $($entry.Path)")
            $lines.Add("[FAIL] $($entry.Label): $($entry.Path)")
        }
    }

    $whisperPaths = Get-SlopWhisperPaths -InstallRoot $root `
        -CliFile ([string]$cfg.whisperRuntimeFile) -ModelFile ([string]$cfg.whisperModelFile)
    $whisperReady = Test-SlopWhisperReady -Paths $whisperPaths
    if ($whisperReady.Ok) { $lines.Add("[OK] Whisper CLI: $($whisperPaths.Cli)") }
    else {
        $errors.AddRange([string[]]$whisperReady.Errors)
        foreach ($message in $whisperReady.Errors) { $lines.Add("[FAIL] Whisper CLI/model: $message") }
    }

    if (Test-Path -LiteralPath $whisperPaths.Model -PathType Leaf) {
        $integrityParams = @{ Paths = $whisperPaths }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedModelSha1)) { $integrityParams.ExpectedSha1 = $ExpectedModelSha1 }
        $integrity = Test-SlopWhisperIntegrity @integrityParams
        if ($integrity.Ok) { $lines.Add("[OK] Whisper model SHA-1: $($integrity.Actual)") }
        else {
            $errors.Add($integrity.Reason)
            $lines.Add("[FAIL] Whisper model SHA-1: expected $($integrity.Expected), got $($integrity.Actual)")
        }
    }

    return @{ Ok = ($errors.Count -eq 0); Lines = $lines.ToArray(); Errors = $errors.ToArray() }
}

if ($MyInvocation.InvocationName -ne '.') {
    $report = Invoke-SlopPreflight -InstallRoot $InstallRoot -ConfigPath $ConfigPath -ExpectedModelSha1 $ExpectedModelSha1
    $report.Lines | ForEach-Object { Write-Host $_ }
    if (-not $report.Ok -and -not $ReportOnly) { exit 1 }
}
```

The invocation guard makes dot-sourcing from `Slop.ps1` side-effect-free. mmproj is deliberately not a required artifact: it stays an unused readiness hook.

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-preflight-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add tools/slop-preflight.ps1 tests/slop-preflight-check.ps1
git commit -m "feat(preflight): headless Tier 1 readiness report"
git diff --check
```

Expected: preflight suite `5/5`; canonical verify stays green with 5 new tests.

---

## Task 4 — Settings voice controls (RED → GREEN)

Files: `tests/slop-shell-check.ps1`, `src/Slop.ps1`.

### 4a. RED static tests

Append these lines to `tests/slop-shell-check.ps1` above the final `Describe` block. Also add `'VoiceEnabledCheck','VoiceLanguageCombo','VoiceMaxSecondsBox','VoiceRepairButton','VoiceReadyText'` to the existing XAML element name array at line 16.

```powershell
Assert-True ($src -match 'Slop\.Audio\.ps1') 'headless audio module is dot-sourced by the shell'
Assert-True ($src -match 'slop-preflight\.ps1') 'preflight tool is dot-sourced by the shell'
Assert-True ($src -match '\$VoiceEnabledCheck\.IsChecked = \[bool\]\$cfg\.voiceEnabled') 'Settings loads voiceEnabled from config'
Assert-True ($src -match '\$VoiceLanguageCombo\.Text = \[string\]\$cfg\.whisperLanguage') 'Settings loads whisperLanguage from config'
Assert-True ($src -match '\$VoiceMaxSecondsBox\.Text = \[string\]\$cfg\.voiceMaxSeconds') 'Settings loads voiceMaxSeconds from config'
Assert-True ($src -match '\$cfg\.voiceEnabled = \[bool\]\$VoiceEnabledCheck\.IsChecked') 'Settings saves voiceEnabled'
Assert-True ($src -match '\$cfg\.whisperLanguage = \(\[string\]\$VoiceLanguageCombo\.Text\)\.Trim\(\)\.ToLowerInvariant\(\)') 'Settings saves a normalized whisperLanguage'
Assert-True ($src -match '\[int\]::TryParse\(\[string\]\$VoiceMaxSecondsBox\.Text') 'Settings saves a validated voiceMaxSeconds'
Assert-True ($src -match 'Invoke-SlopPreflight -InstallRoot \$script:VoiceInstallRoot') 'Repair voice runs the report-only preflight'
Assert-True ($src -match 'Get-SlopVoiceReadinessText -Config \$cfg') 'Settings shows exact Whisper readiness'
```

Run RED:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
git add tests/slop-shell-check.ps1
git commit -m "test(shell): red Settings voice wiring checks"
```

### 4b. GREEN source

Dot-source the new module and the preflight tool after `src/Slop.Config.ps1` (current `src/Slop.ps1:15`), so all later code can use both:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Config.ps1')
. (Join-Path $PSScriptRoot 'Slop.Audio.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/slop-preflight.ps1')
```

Set the install root once, beside `$script:PendingAttachments` (current line 25):

```powershell
$script:VoiceInstallRoot = Get-SlopVoiceInstallRoot
```

Insert this voice XAML immediately after the `SettingsAgentIdBox` TextBox (current `src/Slop.ps1:150`), before `SettingsSaveButton`:

```powershell
                  <TextBlock Text="Voice input" Foreground="#93A4BD" FontSize="10" FontWeight="SemiBold" Margin="6,4,6,4"/>
                  <CheckBox x:Name="VoiceEnabledCheck" Content="Voice enabled (local transcription, off by default)"
                            Foreground="#B8B8C0" FontSize="10" Margin="6,0,6,6"/>
                  <TextBlock Text="Language" Foreground="#B8B8C0" FontSize="10" Margin="6,0,6,2"/>
                  <ComboBox x:Name="VoiceLanguageCombo" Height="26" FontSize="11" Margin="6,0,6,6" Width="140"
                            HorizontalAlignment="Left"/>
                  <TextBlock Text="Max seconds" Foreground="#B8B8C0" FontSize="10" Margin="6,0,6,2"/>
                  <TextBox x:Name="VoiceMaxSecondsBox" Height="26" FontSize="11" Width="80" Margin="6,0,6,6"
                           HorizontalAlignment="Left" Padding="6,3" VerticalContentAlignment="Center"/>
                  <Button x:Name="VoiceRepairButton" Content="Repair voice" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="10" Margin="6,0,6,6"
                          Background="#22FFFFFF" Foreground="#EAEAEA" Padding="10,4"/>
                  <TextBlock x:Name="VoiceReadyText" Text="Whisper readiness: unknown" Foreground="#8A8A96"
                             FontSize="10" TextWrapping="Wrap" Margin="6,0,6,10"/>
```

The `Style="{StaticResource SlopButton}"` reference resolves in the real Window resource dictionary; the isolated XAML probe used a plain Button because a detached StackPanel has no such resource.

Add FindName lookups after `$SettingsAgentIdBox` (current line 326):

```powershell
$VoiceEnabledCheck = $window.FindName('VoiceEnabledCheck')
$VoiceLanguageCombo = $window.FindName('VoiceLanguageCombo')
$VoiceMaxSecondsBox = $window.FindName('VoiceMaxSecondsBox')
$VoiceRepairButton = $window.FindName('VoiceRepairButton')
$VoiceReadyText = $window.FindName('VoiceReadyText')
foreach ($language in Get-SlopWhisperLanguages) { $VoiceLanguageCombo.Items.Add($language) | Out-Null }
```

Add this helper immediately before `Load-SlopSettings`:

```powershell
function Update-SlopVoiceReadinessUi {
    $cfg = $script:SlopConfigResult.Config
    if ($null -eq $cfg) { return }
    $VoiceEnabledCheck.IsChecked = [bool]$cfg.voiceEnabled
    $VoiceLanguageCombo.Text = [string]$cfg.whisperLanguage
    $VoiceMaxSecondsBox.Text = [string]$cfg.voiceMaxSeconds
    $VoiceReadyText.Text = 'Whisper readiness: ' + (Get-SlopVoiceReadinessText -Config $cfg -InstallRoot $script:VoiceInstallRoot)
}
```

Extend `Load-SlopSettings` (current lines 942-951) with one call before its closing `}`. The helper owns the field assignments, so do not duplicate them here:

```powershell
    Update-SlopVoiceReadinessUi
```

`Update-SlopVoiceReadinessUi` deliberately does **not** call `Set-SlopMicUiState` yet: that function arrives in Task 6. This keeps the intermediate Task 4 state runnable. Task 6 adds the line.

Extend `Save-SlopSettings` (current lines 953-980) by inserting after `$cfg.agentId` is normalized. Use `TryParse` so a blank or garbage field reports through the existing thought-bubble path instead of throwing at the WPF edge:

```powershell
    $cfg.voiceEnabled = [bool]$VoiceEnabledCheck.IsChecked
    $cfg.whisperLanguage = ([string]$VoiceLanguageCombo.Text).Trim().ToLowerInvariant()
    $seconds = 0
    if (-not [int]::TryParse([string]$VoiceMaxSecondsBox.Text, [ref]$seconds)) {
        Add-SlopThoughtBubble -Text 'Max seconds must be an integer between 10 and 120.'
        return $false
    }
    $cfg.voiceMaxSeconds = $seconds
```

Add the repair handler after the `SettingsSaveButton` click handler (find it with `grep` for `SettingsSaveButton.Add_Click`):

```powershell
$VoiceRepairButton.Add_Click({
    try {
        $report = Invoke-SlopPreflight -InstallRoot $script:VoiceInstallRoot -ConfigPath (Get-SlopConfigPath)
        Add-SlopThoughtBubble -Text ($report.Lines -join "`n")
        Update-SlopVoiceReadinessUi
    }
    catch { Add-SlopThoughtBubble -Text "Voice repair failed: $($_.Exception.Message)" }
})
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(settings): local voice controls and repair report"
git diff --check
```

Expected: shell suite green, Settings XAML parses in the real window, verify green.

---

## Task 5 — onboarding Screen 4 voice group (RED → GREEN)

Files: `tests/slop-onboarding-check.ps1`, `src/Slop.Onboarding.ps1`.

### 5a. RED tests

Append inside the `Describe`:

```powershell
    It 'keeps four screens and exposes voice controls on Screen 4' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Match 'x:Name="Screen4"'
        $src | Should -Match 'x:Name="VoiceEnabledCheck"'
        $src | Should -Match 'x:Name="VoiceLanguageCombo"'
        $src | Should -Match 'x:Name="VoiceReadyText"'
        $src | Should -Match 'Get-SlopWhisperLanguages'
        $src | Should -Match 'Get-SlopVoiceReadinessText -Config \$Config'
        $src | Should -Not -Match 'ValidateRange\(1,5\)'
    }

    It 'writes voice settings from the wizard into the version 2 result' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Match '\$result\.voiceEnabled = \[bool\]\$VoiceEnabledCheck\.IsChecked'
        $src | Should -Match '\$result\.whisperLanguage = \(\[string\]\$VoiceLanguageCombo\.SelectedItem\)\.Trim\(\)\.ToLowerInvariant\(\)'
        $fallback = New-SlopFallbackOnboardingResult -Config @{ name = 'Pip'; voiceEnabled = $true }
        (Test-SlopConfig -Config $fallback).Ok | Should -BeTrue
        $fallback.version | Should -Be 2
        $fallback.voiceEnabled | Should -BeTrue
        $fallback.whisperLanguage | Should -Be 'auto'
    }
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-onboarding-check.ps1 -PassThru | Out-Null"
git add tests/slop-onboarding-check.ps1
git commit -m "test(onboarding): red voice screen contracts"
```

### 5b. GREEN source

Insert this XAML after the `BrainNote` TextBlock (current `src/Slop.Onboarding.ps1:166-168`), still inside `Screen4`:

```powershell
            <TextBlock Text="Voice input" Foreground="#93A4BD" FontSize="10" FontWeight="SemiBold" Margin="0,8,0,4"/>
            <CheckBox x:Name="VoiceEnabledCheck" Foreground="#B8B8C0" FontSize="10" Margin="0,2,0,4"
                      Content="Enable voice input (local Whisper small; off by default)"/>
            <ComboBox x:Name="VoiceLanguageCombo" Height="26" FontSize="11" Width="120"
                      HorizontalAlignment="Left" ToolTip="Whisper language"/>
            <TextBlock x:Name="VoiceReadyText" Foreground="#8A8A96" FontSize="10" TextWrapping="Wrap"
                       Margin="0,5,0,0" Text="Whisper readiness: checking"/>
```

Add FindName lookups after `$EffectiveModelText` (current line 217):

```powershell
    $VoiceEnabledCheck = $dlg.FindName('VoiceEnabledCheck')
    $VoiceLanguageCombo = $dlg.FindName('VoiceLanguageCombo')
    $VoiceReadyText = $dlg.FindName('VoiceReadyText')
```

Populate them after the `$ProfileCombo.SelectedItem` assignment (current line 233):

```powershell
    $VoiceEnabledCheck.IsChecked = [bool]$Config.voiceEnabled
    foreach ($language in Get-SlopWhisperLanguages) { $VoiceLanguageCombo.Items.Add($language) | Out-Null }
    $VoiceLanguageCombo.SelectedItem = if ($Config.whisperLanguage) { [string]$Config.whisperLanguage } else { 'auto' }
    $VoiceReadyText.Text = 'Whisper readiness: ' + (Get-SlopVoiceReadinessText -Config $Config)
```

Add to `Get-SlopWizardConfig` after `$result.autostart` (current line 338):

```powershell
        $result.voiceEnabled = [bool]$VoiceEnabledCheck.IsChecked
        $result.whisperLanguage = ([string]$VoiceLanguageCombo.SelectedItem).Trim().ToLowerInvariant()
```

Do not add a fifth screen; do not add a language free-text field; keep `ValidateRange(1,4)`.

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-onboarding-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add src/Slop.Onboarding.ps1 tests/slop-onboarding-check.ps1
git commit -m "feat(onboarding): opt-in voice on Screen 4"
git diff --check
```

Expected: onboarding suite green; verify green.

---

## Task 6 — Mic toggle, local transcription, hard cap (RED → GREEN)

Files: `tests/slop-shell-check.ps1`, `src/Slop.ps1`.

### 6a. RED static tests

Append to `tests/slop-shell-check.ps1`:

```powershell
Assert-True ($src -match 'function Start-SlopVoiceTranscription') 'voice transcription has a named worker starter'
Assert-True ($src -match 'Invoke-SlopWhisperTranscription -Paths \$Paths -WavPath \$Wav') 'voice worker invokes the local Whisper wrapper'
Assert-True ($src -match 'Start-ThreadJob -ScriptBlock \{[\s\S]{0,900}__VOICE__') 'voice job enqueues transcript markers'
Assert-True ($src -match 'Start-Stream -UserText \$tok\.Substring\(9\) -Attachments @\(\)') 'transcript uses the existing text send path'
Assert-True ($src -notmatch '\$MicBtn[\s\S]{0,2400}New-SlopAttachmentFromFile -Path \$script:MicRecorderPath') 'Mic stop no longer attaches the WAV'
Assert-True ($src -match '\$script:VoiceQueue = \[System\.Collections\.Concurrent\.ConcurrentQueue\[string\]\]::new\(\)') 'voice uses a dedicated dispatcher queue'
Assert-True ($src -match '\$script:MicCapTimer\.Interval = \[TimeSpan\]::FromSeconds\(\$script:VoiceMaxSeconds\)') 'hard recording cap is configured from voiceMaxSeconds'
Assert-True ($src -match 'Remove-Item -LiteralPath \$Wav -Force -ErrorAction SilentlyContinue') 'temporary WAV is deleted in the worker finally block'
Assert-True ($src -match '\$SendBtn\.IsEnabled = -not \[bool\]\$script:IsStreaming') 'voice idle state never re-enables Send during a stream'
Assert-True ($src -match "tok\.StartsWith\('__VOICE__'\)") 'voice success marker is handled before plain text'
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
git add tests/slop-shell-check.ps1
git commit -m "test(shell): red Mic-to-transcript checks"
```

### 6b. GREEN source

Replace the current Mic block (`src/Slop.ps1:1668-1711`, from `$script:MicRecording = $false` through the closing `})` of `$MicBtn.Add_Click`) with the probe-parsed block below. Keep the Attach button block above it unchanged.

```powershell
$script:MicRecording = $false
$script:MicRecorderPath = $null
$script:MicCapTimer = $null
$script:VoiceBusy = $false
$script:VoiceMaxSeconds = 30
$script:VoiceQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

function Set-SlopMicUiState {
    param([ValidateSet('idle','recording','transcribing')][string]$State)
    if ($State -eq 'recording') {
        $MicBtn.Content = '■'
        $MicBtn.ToolTip = 'Recording... click to stop'
        $MicBtn.IsEnabled = $true
        $SendBtn.IsEnabled = $false
    }
    elseif ($State -eq 'transcribing') {
        $MicBtn.Content = '⏳'
        $MicBtn.ToolTip = 'Transcribing locally...'
        $MicBtn.IsEnabled = $false
        $SendBtn.IsEnabled = $false
    }
    else {
        $MicBtn.Content = '🎤'
        $MicBtn.ToolTip = if ($script:SlopConfigResult.Config.voiceEnabled) { 'Voice note to text (click to start/stop)' } else { 'Enable voice input in Settings' }
        $MicBtn.IsEnabled = [bool]$script:SlopConfigResult.Config.voiceEnabled
        $SendBtn.IsEnabled = -not [bool]$script:IsStreaming
    }
}

function Start-SlopVoiceTranscription {
    param([Parameter(Mandatory)][string]$WavPath)
    $cfg = $script:SlopConfigResult.Config
    $paths = Get-SlopWhisperPaths -InstallRoot $script:VoiceInstallRoot `
        -CliFile ([string]$cfg.whisperRuntimeFile) -ModelFile ([string]$cfg.whisperModelFile)
    $ready = Test-SlopWhisperReady -Paths $paths
    if (-not $ready.Ok) {
        Add-Bubble -Text "[error: voice input unavailable: $($ready.Errors -join '; ')]" -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    $script:VoiceBusy = $true
    Set-SlopMicUiState -State transcribing
    Start-ThreadJob -ScriptBlock {
        param($AudioModule, $Paths, $Wav, $Language, $Queue)
        try {
            . $AudioModule
            $result = Invoke-SlopWhisperTranscription -Paths $Paths -WavPath $Wav -Language $Language -TimeoutSeconds 90
            if (-not $result.Ok) { $Queue.Enqueue("__VOICEERR__$($result.Reason)"); return }
            if ([string]::IsNullOrWhiteSpace($result.Text)) { $Queue.Enqueue('__VOICEERR__I did not catch that.'); return }
            $Queue.Enqueue("__VOICE__$($result.Text)")
        }
        catch { $Queue.Enqueue("__VOICEERR__$($_.Exception.Message)") }
        finally {
            if (Test-Path -LiteralPath $Wav) { Remove-Item -LiteralPath $Wav -Force -ErrorAction SilentlyContinue }
            $Queue.Enqueue('__VOICEDONE__')
        }
    } -ArgumentList (Join-Path $PSScriptRoot 'Slop.Audio.ps1'), $paths, $WavPath, ([string]$cfg.whisperLanguage), $script:VoiceQueue
}

function Stop-SlopMicAndTranscribe {
    if (-not $script:MicRecording) { return }
    $script:MicRecording = $false
    if ($script:MicCapTimer) { $script:MicCapTimer.Stop() }
    [SlopWinMM]::mciSendString('stop slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
    [SlopWinMM]::mciSendString(('save slopmic "' + $script:MicRecorderPath + '"'), $null, 0, [IntPtr]::Zero) | Out-Null
    [SlopWinMM]::mciSendString('close slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
    $wav = $script:MicRecorderPath
    $script:MicRecorderPath = $null
    if (-not $wav -or -not (Test-Path -LiteralPath $wav -PathType Leaf)) {
        Add-Bubble -Text '[error: microphone recording was not saved]' -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    if ((Get-Item -LiteralPath $wav).Length -le 44) {
        Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue
        Add-Bubble -Text '[error: microphone recording was empty]' -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    Start-SlopVoiceTranscription -WavPath $wav
}

$script:VoiceTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:VoiceTimer.Interval = [TimeSpan]::FromMilliseconds(40)
$script:VoiceTimer.Add_Tick({
    $q = $script:VoiceQueue
    if ($null -eq $q) { return }
    $tok = $null
    while ($q.TryDequeue([ref]$tok)) {
        if ($tok.StartsWith('__VOICE__')) {
            # Start-Stream already adds the user bubble; do not add it twice.
            Start-Stream -UserText $tok.Substring(9) -Attachments @()
        }
        elseif ($tok.StartsWith('__VOICEERR__')) {
            Add-Bubble -Text "[error: $($tok.Substring(12))]" -IsUser $false
            Set-SlopMicUiState -State idle
        }
        elseif ($tok -eq '__VOICEDONE__') { Set-SlopMicUiState -State idle }
    }
})
$script:VoiceTimer.Start()

$script:MicCapTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MicCapTimer.Add_Tick({
    if ($script:MicRecording) {
        Stop-SlopMicAndTranscribe
        Add-Bubble -Text "Recording stopped at the $($script:VoiceMaxSeconds)s limit." -IsUser $false
    }
})

$MicBtn.Add_Click({
    try {
        if ($script:VoiceBusy) { return }
        if ($script:IsStreaming) {
            Add-Bubble -Text 'Wait for the current reply before starting a voice note.' -IsUser $false
            return
        }
        $cfg = $script:SlopConfigResult.Config
        if (-not $cfg.voiceEnabled) {
            Add-Bubble -Text 'Enable voice input in Settings.' -IsUser $false
            return
        }
        if ($script:MicRecording) { Stop-SlopMicAndTranscribe; return }
        if (-not ('SlopWinMM' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SlopWinMM {
  [DllImport("winmm.dll", CharSet=CharSet.Auto)] public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);
}
"@
        }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("slop-mic-" + [guid]::NewGuid().ToString('N') + '.wav')
        $script:MicRecorderPath = $tmp
        [SlopWinMM]::mciSendString('open new type waveaudio alias slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
        $result = [SlopWinMM]::mciSendString('record slopmic', $null, 0, [IntPtr]::Zero)
        if ($result -ne 0) { throw "winmm record failed (code $result)" }
        $script:MicRecording = $true
        $script:VoiceMaxSeconds = [int]$cfg.voiceMaxSeconds
        $script:MicCapTimer.Interval = [TimeSpan]::FromSeconds($script:VoiceMaxSeconds)
        $script:MicCapTimer.Start()
        Set-SlopMicUiState -State recording
    }
    catch {
        $script:MicRecording = $false
        if ($script:MicCapTimer) { $script:MicCapTimer.Stop() }
        try { [SlopWinMM]::mciSendString('close slopmic', $null, 0, [IntPtr]::Zero) | Out-Null } catch {}
        if ($script:MicRecorderPath -and (Test-Path -LiteralPath $script:MicRecorderPath)) {
            Remove-Item -LiteralPath $script:MicRecorderPath -Force -ErrorAction SilentlyContinue
        }
        $script:MicRecorderPath = $null
        Set-SlopMicUiState -State idle
        Add-Bubble -Text "[error: mic recording unavailable: $($_.Exception.Message)]" -IsUser $false
    }
})
```

Now that `Set-SlopMicUiState` exists, append this line to the end of `Update-SlopVoiceReadinessUi` (added in Task 4):

```powershell
    Set-SlopMicUiState -State idle
```

Add the same call inside `Finish-Stream` immediately after `$SendBtn.IsEnabled = $true`:

```powershell
    Set-SlopMicUiState -State idle
```

Add one bootstrap call after config resolution at current `src/Slop.ps1:1791` (after the onboarding `elseif` block) so a voice-disabled Mic button stays disabled from startup:

```powershell
Set-SlopMicUiState -State idle
```

Why this shape:

- DispatcherTimer tick scriptblocks do not capture function locals; all state used by the ticks is published to `$script:` scope.
- `__VOICEDONE__` follows both success and error; idle state is restored on every path.
- `Start-Stream` already creates the user bubble, so the voice tick does not duplicate it.
- The WAV is deleted in the thread-job `finally`, never attached and never logged.
- `$script:VoiceBusy` and the `IsStreaming` guard prevent overlapping voice/chat work.

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(voice): push-to-talk transcription through the text path"
git diff --check
```

Expected: shell suite green; verify green. This is still **headless only** — no live claim.

---

## Task 7 — LFS rules, notices, docs (RED → GREEN)

Files: `.gitattributes`, `docs/third-party-notices.md` (new), `README.md`, `docs/architecture.md`, `tests/slop-shell-check.ps1`.

### 7a. RED static tests

Append to `tests/slop-shell-check.ps1`:

```powershell
$gitattributes = Get-Content (Join-Path $PSScriptRoot '../.gitattributes') -Raw
$noticesPath = Join-Path $PSScriptRoot '../docs/third-party-notices.md'
$readme = Get-Content (Join-Path $PSScriptRoot '../README.md') -Raw
$architecture = Get-Content (Join-Path $PSScriptRoot '../docs/architecture.md') -Raw
Assert-True ($gitattributes -match 'runtime/whisper/\*\* filter=lfs') 'Whisper runtime is tracked with Git LFS'
Assert-True ($gitattributes -match '\*\.bin filter=lfs') 'Whisper model .bin files are tracked with Git LFS'
Assert-True (Test-Path $noticesPath) 'third-party notices file exists'
if (Test-Path $noticesPath) {
    $notices = Get-Content $noticesPath -Raw
    Assert-True ($notices -match 'whisper\.cpp') 'notices name whisper.cpp'
    Assert-True ($notices -match 'MIT') 'notices record the MIT license'
    Assert-True ($notices -match '55356645c2b361a969dfd0ef2c5a50d530afd8d5') 'notices pin the small model SHA-1'
}
Assert-True ($readme -match 'opt-in push-to-talk audio is transcribed locally') 'README documents shipped local voice transcription'
Assert-True ($architecture -match 'bundled Whisper small') 'architecture documents local voice input'
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
git add tests/slop-shell-check.ps1
git commit -m "test(docs): red Whisper LFS and notice checks"
```

### 7b. GREEN files

Append to `.gitattributes`:

```text
# Whisper runtime and model artifacts for Tier 1 voice input
runtime/whisper/** filter=lfs diff=lfs merge=lfs -text
*.bin filter=lfs diff=lfs merge=lfs -text
```

Create `docs/third-party-notices.md`:

```markdown
# Third-party notices

## whisper.cpp

- Project: https://github.com/ggml-org/whisper.cpp
- License: MIT (https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)
- Used for: local speech-to-text only. Sloppy invokes `whisper-cli` per utterance and never uploads audio.

## Whisper small model

- File: `runtime/whisper/models/ggml-small.bin`
- Published filename and checksum: https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- SHA-1: `55356645c2b361a969dfd0ef2c5a50d530afd8d5`

The checksum is verified by `tools/slop-preflight.ps1`. Release-time license review is a separate gate; this file records provenance, it does not authorize a release.
```

Replace the stale sentence in `README.md:92` with:

```markdown
Sloppy prefers whatever OpenCode config you already have. If there is none, it installs a minimal zero-trust config; it never overwrites an active one. The bundled Gemma 4 E2B brain answers text locally, and opt-in push-to-talk audio is transcribed locally by bundled Whisper small before being sent through the same text path. Nothing is uploaded for Tier 1. Image capture and `mmproj` remain unused readiness hooks; there are no spoken replies.
```

Replace `docs/architecture.md:123` with:

```markdown
Tier 1 local brain is bundled for local-first operation: `runtime/llama-b12676-bin-win-cuda-13.5-x64/llama-server.exe`, `runtime/models/gemma-4-E2B_q4_0-it.gguf`, and `runtime/models/gemma-4-E2B-it-mmproj.gguf`. Large runtime/model artifacts are tracked via Git LFS; HF download cache under `runtime/models/.cache/` is ignored. Text requests use the existing llama.cpp adapter. Opt-in voice input records a short WAV with WinMM, transcribes it locally with bundled Whisper small through `src/Slop.Audio.ps1`, and sends the transcript through the same text path. No audio leaves the machine, and there is no TTS or VAD. `mmproj` and `localVisionReady` stay unused readiness hooks; Tier 1 makes no image claim.
```

Also add a Requirements bullet under `README.md:87-90`:

```markdown
- Optional for voice: bundled `whisper-cli.exe` and `ggml-small.bin` under `runtime/whisper/` (Git LFS)
```

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
git add .gitattributes docs/third-party-notices.md README.md docs/architecture.md tests/slop-shell-check.ps1
git commit -m "docs(tier1): Whisper notices, LFS rules and honest README"
git diff --check
```

Do not add the model binary or CLI to a commit in this repo; they are Git LFS artifacts supplied by the release bundle, and this plan does not touch release artifacts.

---

## Task 8 — tour anchors and final gates

After all source edits, refresh the 18-step tour using the probe-validated text-fragment script. Save it to a disposable path outside the repo (never commit it):

```powershell
#requires -Version 7.6
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$TourPath
)
$ErrorActionPreference = 'Stop'

$anchorMap = @{
    1  = @{ File = 'docs/architecture.md'; Text = 'Status: accepted' }
    3  = @{ File = 'src/Slop.ps1'; Text = 'Add-Type -AssemblyName PresentationFramework' }
    4  = @{ File = 'src/Slop.Motion.ps1'; Text = 'function New-SlopMotionState' }
    5  = @{ File = 'src/Slop.Motion.ps1'; Text = 'function Get-SlopIdleAction' }
    6  = @{ File = 'src/Slop.Frame.ps1'; Text = 'public sealed class SlopFrame' }
    7  = @{ File = 'src/Slop.Frame.ps1'; Text = 'void Build()' }
    8  = @{ File = 'src/Slop.Face.ps1'; Text = 'function New-SlopFaceLayer' }
    9  = @{ File = 'src/Slop.Lifecycle.ps1'; Text = 'function New-SlopRequestState' }
    10 = @{ File = 'src/Slop.OpenCode.ps1'; Text = 'function Test-SlopOpenCodeConfig' }
    11 = @{ File = 'src/Slop.ps1'; Text = 'function Start-Stream' }
    12 = @{ File = 'src/Slop.ps1'; Text = 'function Add-SlopApprovalCard' }
    13 = @{ File = 'src/Slop.ps1'; Text = 'function Request-StopStream' }
    14 = @{ File = 'src/Slop.Sense.ps1'; Text = 'function Invoke-SlopSenseScan' }
    15 = @{ File = 'src/Slop.ps1'; Text = 'function Expand-Chat' }
    16 = @{ File = 'src/Slop.ps1'; Text = '$script:MotionTimer = [System.Windows.Threading.DispatcherTimer]::new()' }
    17 = @{ File = 'src/Slop.ps1'; Text = 'function Apply-SlopMotion' }
}

$tour = Get-Content -LiteralPath $TourPath -Raw | ConvertFrom-Json
$i = 0
foreach ($step in $tour.steps) {
    $i++
    if (-not $anchorMap.ContainsKey($i)) { continue }
    $anchor = $anchorMap[$i]
    $path = Join-Path $Root $anchor.File
    $lines = @(Get-Content -LiteralPath $path)
    $match = $null
    for ($n = 0; $n -lt $lines.Count; $n++) {
        if ($lines[$n].IndexOf($anchor.Text, [StringComparison]::Ordinal) -ge 0) { $match = $n + 1; break }
    }
    if ($null -eq $match) { throw "step $i anchor not found in $($anchor.File): $($anchor.Text)" }
    if ($null -eq $step.file -or $step.file -ne $anchor.File) { throw "step $i file mismatch: expected $($anchor.File), got $($step.file)" }
    $step.line = $match
    Write-Host "step $i -> $($anchor.File):$match"
}

$json = $tour | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($TourPath, $json + "`n", [Text.UTF8Encoding]::new($false))
```

Run it against a copy, verify, then copy back and commit only the tour file:

```powershell
$root = (Get-Location).Path
$tour = Join-Path $root '.tours/architect-slop-architecture.tour'
$tmp = Join-Path $env:TEMP 'tier1-architect.tour'
Copy-Item $tour $tmp -Force
pwsh -NoProfile -File (Join-Path $env:TEMP 'tier1-refresh-tour-anchors.ps1') -Root $root -TourPath $tmp
Copy-Item $tmp $tour -Force
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-tour-check.ps1 -PassThru | Out-Null"
git add .tours/architect-slop-architecture.tour
git commit -m "docs(tour): refresh anchors after Tier 1 voice edits"
git diff --check
```

The tour's inline line references at `.tours/architect-slop-architecture.tour:58` and `:64` point to unchanged modules (`Slop.Motion.ps1` and `Slop.Frame.ps1`), so they should not need edits. If the tour check disagrees, fix the specific reference in the same commit.

Final gate sequence — run all of these and paste the output into the execution report:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-audio-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-preflight-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-config-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-shell-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-onboarding-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\slop-tour-check.ps1 -PassThru | Out-Null"
pwsh -NoProfile -File "$HOME\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
pwsh -NoProfile -File "$HOME\.agents\scripts\review.ps1" -ProjectPath (Get-Location).Path
git diff --check
git status --short --branch
```

Acceptance: every suite green, canonical verify `All gates passed.`, tour 38/38, review exit `0`, `git diff --check` silent, no untracked `security-scan-results.json` in any commit.

---

## Commit map (explicit paths only)

| Task | RED commit | GREEN commit |
|---|---|---|
| Config v2 | `test(config): red Tier 1 voice config v2` | `feat(config): version 2 Tier 1 voice schema and migration` |
| Audio | `test(audio): red Whisper wrapper contracts` | `feat(audio): headless local Whisper transcription module` |
| Preflight | `test(preflight): red Tier 1 readiness report contracts` | `feat(preflight): headless Tier 1 readiness report` |
| Settings | `test(shell): red Settings voice wiring checks` | `feat(settings): local voice controls and repair report` |
| Onboarding | `test(onboarding): red voice screen contracts` | `feat(onboarding): opt-in voice on Screen 4` |
| Mic | `test(shell): red Mic-to-transcript checks` | `feat(voice): push-to-talk transcription through the text path` |
| Docs | `test(docs): red Whisper LFS and notice checks` | `docs(tier1): Whisper notices, LFS rules and honest README` |
| Tour | — | `docs(tour): refresh anchors after Tier 1 voice edits` |

Never use `git add -A`, never amend a user commit, never include `security-scan-results.json`, and leave release-readiness files untouched.

## Hard gate that code cannot pass

Headless tests with a fake CLI do not prove mic capture or Whisper behavior. Tier 1 is **not done** until a real mic + real Whisper small smoke confirms:

1. clean install starts with voice disabled;
2. toggling voice on in Settings or onboarding persists across restart;
3. first Mic press starts recording, second press transcribes locally and sends the transcript as a normal text message;
4. the 30-second cap stops a runaway recording;
5. no audio or transcript leaves the machine and no Tier 2 route is touched;
6. after completion/error the temp WAV is gone and Mic/Send states are correct.

At recon there were no bundled Whisper artifacts and no `SLOP_LIVE_*` overrides, so this smoke was deferred. If it remains unavailable at execution time, report Tier 1 as **code-complete, live-smoke deferred** — not done.
