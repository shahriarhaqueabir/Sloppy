# Sloppy — Provider-Specific Security Architecture

## Objective

Sloppy is the WPF desktop frontend. Its intelligence backend can be switched between:

- OpenCode
- Claude Code
- Cloud AI APIs
- Local LLMs

Each backend has different capabilities, attack surfaces and vulnerabilities. Therefore, Sloppy must use a dedicated security configuration for each connection type rather than applying identical permissions everywhere.

## 1. Two-Layer Security Architecture

### Global Security Policy

Immutable restrictions applying to every provider:

- AI models never receive Windows credentials.
- No automatic administrator privileges.
- All PC operations pass through Sloppy's execution broker.
- File deletion requires explicit approval.
- Sensitive operations require explicit approval.
- Network access is restricted.
- Security policy changes require explicit approval.
- Cancellation must immediately stop execution.
- Security events are audited.
- Provider switching creates a new security context.

### Provider-Specific Security Profiles

Each provider has its own:
- Permission matrix.
- Tool allowlist.
- Network restrictions.
- Filesystem restrictions.
- Credential configuration.
- Session management.
- Security diagnostics.
- Vulnerability-specific mitigations.

## 2. Provider Security Requirements

### OpenCode
- Dedicated restricted Sloppy agent.
- Deny-by-default permissions.
- Hard-deny dangerous tools and integrations.
- Restrict external directories.
- Restrict web access and SSRF targets.
- Disable subagents, MCP and plugins by default.
- One-time approvals only.
- Verify agent selection before prompting.
- Validate configuration precedence.

Primary risks: permission inheritance, shell execution, saved approvals and configuration precedence.

### Claude Code
- Enable filesystem and network sandboxing.
- Restrict accessible directories.
- Explicit tool allowlists.
- PreToolUse hooks for sensitive operations.
- Disable permission-bypass modes.
- Restrict MCP servers and extensions.

Primary risks: shell escape, prompt injection, hooks and extension trust.

### Cloud API
- No direct access to local PC.
- Send minimum necessary context.
- Redact sensitive information.
- Keep API keys outside model context.
- Validate structured tool calls.
- Execute local operations through Sloppy's broker.
- Use isolated remote execution environments where required.

Primary risks: data exfiltration, prompt injection, credential exposure and remote execution.

### Local LLM
- Bind inference server to localhost.
- Prevent unauthenticated LAN access.
- No direct filesystem or shell access.
- Validate structured tool calls.
- Apply resource and request limits.
- Separate inference process from privileged services.
- Use the same approval broker as other providers.

Primary risks: malicious model output, exposed local endpoints and uncontrolled tool execution.

## 3. Settings Interface

Create a dedicated connection settings page.

Users should be able to:
- Select the active intelligence provider.
- Configure provider-specific settings.
- Select Strict, Balanced or Custom security profiles.
- Configure individual tool permissions.
- Manage credentials.
- Inspect active restrictions.
- Review security events.
- Test and validate configurations.

Security profiles are presets, not substitutes for the global security policy.

## 4. Permission Model

Support three permission levels:

- Allow: Permitted within configured boundaries.
- Ask: Requires explicit user approval.
- Deny: Blocked.

The global policy must always take precedence over provider-specific settings.

Provider-native permission systems are additional safeguards, never Sloppy's ultimate security authority.

## 5. Architecture

```text
sloppy/
├── config/
│   ├── global-security.json
│   ├── providers/
│   │   ├── opencode.json
│   │   ├── claude-code.json
│   │   ├── cloud-api.json
│   │   └── local-llm.json
│   ├── permissions/
│   └── profiles/
│       ├── strict.json
│       ├── balanced.json
│       └── custom.json
├── security/
│   ├── policy-engine
│   ├── approval-broker
│   ├── execution-broker
│   ├── credential-manager
│   └── audit-log
└── providers/
    ├── opencode/
    ├── claude-code/
    ├── cloud/
    └── local/
```

## 6. Provider Switching

When switching providers:
1. Cancel active operations.
2. Reject pending approvals.
3. Close or isolate the previous session.
4. Load the new provider's security profile.
5. Validate its configuration.
6. Establish a new session.
7. Verify effective permissions before accepting prompts.

Never inherit permissions or credentials from the previous provider.

## 7. Development Priorities

1. Implement the global security policy engine.
2. Implement the permission and execution brokers.
3. Build the provider adapter architecture.
4. Implement OpenCode security profile first.
5. Add Claude Code, cloud API and local LLM profiles.
6. Build provider-specific settings interfaces.
7. Create dedicated security tests for each provider.
8. Test provider switching, cancellation, permission escalation and isolation.

## Core Principle

**Models decide what they want to do. Sloppy decides what they are allowed to do.**

Every provider is treated as untrusted. No provider can bypass Sloppy's global security enforcement, regardless of its native permission system or model capabilities.
