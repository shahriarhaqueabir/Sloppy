# Sloppy — Settings & Control Panel Specification

Build a dedicated settings interface for configuring Sloppy's appearance, personality, intelligence, permissions and capabilities.

## 1. Appearance
- Custom colour palettes and themes.
- Randomised pixel patterns to create different facial expressions.
- Preset expressions for idle, listening, thinking, success and errors.
- Pixel density, expression intensity and animation speed.
- Idle behaviour and animation controls.
- Preview changes live.

Keep facial expressions separate from the underlying status indicators.

## 2. Personality
- Personality presets: Calm, Playful, Curious, Professional.
- Communication style: Concise, Balanced, Detailed.
- Humour frequency.
- Proactivity level.
- Memory preferences.
- Editable custom personality instructions.

## 3. Permissions & Security
Provide granular controls for:
- File reading, creation, modification and deletion.
- Folder-specific access.
- Browser and web access.
- PowerShell and terminal execution.
- Application access.
- Network access.
- Software installation.

Permission options:
- Allow
- Ask every time
- Deny

Include permission history, revocation and approval management.

**Security requirement:** User-configurable permissions must never override immutable security policies. Enforce restrictions in the bridge and OpenCode policy layer, not merely through the UI.

## 4. Intelligence
- AI provider and model selection.
- Local/cloud model preference.
- Temperature and response limits.
- Context window settings.
- Memory and conversation history.
- Default agent.
- Model fallback configuration.

## 5. Instructions, Skills & Workflows
Provide management interfaces for:
- Core identity instructions.
- Behavioural instructions.
- User preferences.
- Safety rules.
- Skills and tools.
- Reusable workflows.

Support editing, enabling/disabling, version history and restoration.

## 6. System & Diagnostics
- OpenCode connection status.
- Local model status.
- Browser connection.
- Active session and agent.
- Available tools.
- Current permissions.
- Activity and error logs.
- Configuration validation.
- Backup, restore and reset.

## 7. Operating Profiles
Provide three configurable presets:

- **Companion:** Conversation, memory and minimal tool access.
- **Assistant:** Research, notes, files and browser.
- **Operator:** Broad tool access, with explicit approval for consequential actions.

Profiles are presets, not separate agents or independent security boundaries.

## 8. Interface Structure

```text
SLOPPY SETTINGS
├── Appearance
├── Personality
├── Intelligence
├── Permissions
├── Instructions
├── Skills & Tools
└── System & Diagnostics
```

## 9. Configuration Architecture

Use separate configuration files for:
- Appearance
- Personality
- Model preferences
- User-configurable permissions
- Instructions
- Skills and workflows

Keep security enforcement separate and authoritative.

Changes should be validated before application. Support configuration versioning, rollback and backup.

## Design Objective

Create a settings system that makes Sloppy highly customisable without compromising its security architecture. Appearance and personality should be easy to experiment with; permissions and system configuration should be transparent, auditable and controlled.
