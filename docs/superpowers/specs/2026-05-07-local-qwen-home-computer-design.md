# Local Qwen Home Computer Design

## Scope

Create a new public repository that packages a working local `llama.cpp + TurboQuant + Qwen 3.6 35B A3B + OpenCode` setup into a clean installable project for both Windows and Linux.

## Architecture

The project will use a mono-repo structure with platform-specific installers and a shared launcher/configuration layer.

- `install/windows/`
- `install/linux/`
- `launcher/`
- `config/profiles/`
- `assets/icons/`
- `docs/`

## Components

### Windows installer

Installs dependencies, fetches `llama.cpp`, builds or installs `TurboQuant`, configures `OpenCode`, installs the control center, and creates desktop launchers.

### Linux installer

Performs the Linux equivalent with shell-based setup, distro-aware package hints, and desktop launcher generation where supported.

### Shared launcher layer

Contains the logic for:

- starting/stopping `llama.cpp`
- selecting profiles
- saving context/output/step settings
- launching `OpenCode`
- choosing agent security and autonomy modes

### Shared config

Machine-readable configuration for:

- model selection
- hardware profiles
- context/output defaults
- safe agent mode presets

## Data flow

1. Installer detects platform and hardware.
2. Installer selects default profile and recommended model.
3. Installer writes local runtime config and OpenCode config.
4. Control center loads saved settings and launches tools.
5. Agent mode launcher generates a session-scoped OpenCode permission config.

## Error handling

- Dependency install failures should stop with clear recovery steps.
- Missing GPU/CUDA support should fall back to documented CPU-safe or reduced-mode guidance.
- Model download failures should be resumable.
- OpenCode configuration should be validated after write.

## Testing

- Smoke tests for Windows scripts
- Smoke tests for Linux scripts
- Config generation tests
- Launcher parse checks
- Post-install verification checks

## Recommended approach

Use one clean mono-repo and keep existing machine-specific scripts only as reference material while rewriting public scripts to be path-agnostic and reusable.
