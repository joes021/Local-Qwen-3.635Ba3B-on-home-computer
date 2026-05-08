# Installer status

## Shared versioning

Windows and Linux releases intentionally use the same version number.

- `version.json` is shared by both packaging flows
- every release tag `vX.Y.Z` is treated as a cross-platform version label
- the actual code change can still be platform-specific
- if only Windows changed, Linux still gets a refreshed `.run` asset with the same version number
- if only Linux changed, Windows still gets a refreshed `.exe` asset with the same version number
- every release tag now also runs a verifier workflow that waits for all public assets and fails if either platform is missing from the release

Expected public asset set for every tag:

- `Local-Qwen-Setup-X.Y.Z.exe`
- `Local-Qwen-Setup-latest.exe`
- `Local-Qwen-Setup-X.Y.Z.run`
- `Local-Qwen-Setup-latest.run`

## Windows

The current Windows installer now handles:

- install root
- state directory
- latest upstream `llama.cpp` CUDA Windows release download
- `TurboQuant` source clone
- `TurboQuant` build script deployment and optional build during install
- recommended model download through Python + `huggingface_hub`
- `OpenCode` global install through `npm`
- launcher deployment
- icon deployment
- desktop shortcut creation
- unified Windows Control Center with `Pokretanje`, `Podesavanja`, and `Agent` sections
- OpenCode config generation
- post-install verification script
- versioned `Inno Setup` packaging for `Local-Qwen-Setup-a.b.c.exe`
- repair/retry flow for partially completed `LocalQwenHome` installs
- shared runtime recommendation engine
- multi-model catalog with compact and quality quant choices
- diagnostics bundle export
- release update checker
- shared agent risk audit
- onboarding checklist view
- guided next-action workflow
- lifecycle-aware service state that distinguishes `inactive`, `starting / warming`, and `failed`
- live Windows diagnostics tab and Linux diagnostics view tied to the same shared status engine
- shared throughput benchmark history for prompt/output tokens per second, fed by `Test prompt`

Recommended mental model for Windows install order:

1. Bootstrap folders and state
2. Bootstrap CLI/tool dependencies
3. Bootstrap VS Build Tools and CUDA
4. Clone source repos
5. Download upstream `llama.cpp` CUDA binaries
6. Install `OpenCode`
7. Download the default model
8. Write config and saved settings
9. Build `TurboQuant`
10. Create desktop shortcuts

Repair note:

- if a Windows install stops after creating `LocalQwenHome`, rerunning the newest `Setup.exe` is now the intended recovery path
- the installer writes launcher/config/state scaffolding early so retry can continue without manual file copies
- the desktop folder now also includes `Repair Windows App Control` for the common Smart App Control block case
- the Windows Control Center is intended to be the same across machines, instead of a reduced laptop-only variant

Still being finalized:

- more robust CUDA/toolchain auto-recovery when build prerequisites are missing
- hardware-aware fallback logic for more GPUs
- fuller verification pipeline after install

Windows App Control / Smart App Control note:

- if `CiTool.exe -lp -json` shows `VerifiedAndReputableDesktop` with `IsEnforced = true`, Windows Smart App Control can block `llama-server.exe` even if the installer downloaded the correct runtime
- the project now ships `launcher/windows/repair-app-control.ps1` for diagnosis and a best-effort disable flow
- the Windows installer now also creates a `Repair Windows App Control` desktop launcher that opens the same script through a visible wrapper
- expected usage:
  - inspect state:
    - `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\LocalQwenHome\launchers\repair-app-control.ps1"`
  - attempt disable from elevated PowerShell:
    - `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\LocalQwenHome\launchers\repair-app-control.ps1" -DisableSmartAppControl`
- if the endpoint is enterprise-managed, the policy may be redeployed after you disable it locally
- if local security policy blocks unknown unsigned binaries by design, this is not a `llama.cpp` bug; it is an endpoint policy constraint

Release packaging now exists in two forms:

- local build through `packaging/windows/build-setup.ps1`
- GitHub Actions workflow `.github/workflows/windows-setup.yml`
- one-command local cross-platform release through `packaging/release-all.ps1`

If a tag like `vX.Y.Z` is pushed, the workflow publishes `Local-Qwen-Setup-X.Y.Z.exe` to the GitHub release.
It should also publish the stable alias `Local-Qwen-Setup-latest.exe` so README and setup links can always target the newest Windows installer without hardcoded version edits.

## Linux

The current Linux installer is still below Windows parity, but it is no longer just a placeholder.

It currently handles:

- install root creation
- repo clone for `llama.cpp` and `TurboQuant`
- `OpenCode` install via `npm`
- install state output
- interactive installer TUI for Ubuntu 24.04 release flow
- launcher deployment
- OpenCode config writer
- richer terminal control center with settings editing
- separate post-install settings TUI launcher
- `start-opencode.sh`
- desktop launcher files
- post-install verification script
- runtime build through `launcher/linux/build-runtime.sh`
- Ubuntu 24.04-oriented package bootstrap
- self-extract `.run` packaging through `packaging/linux/build-run-installer.sh`
- shared runtime recommendation engine
- multi-model catalog helper via `launcher/linux/manage-models.sh`
- diagnostics bundle export
- release update checker
- shared agent risk audit
- onboarding checklist view
- guided next-action workflow
- lifecycle-aware service state that distinguishes `inactive`, `starting / warming`, and `failed`
- Linux control center diagnostics output based on the same shared status engine used by Windows
- Linux throughput summary and short history fed by `test-prompt.sh`

If a tag like `vX.Y.Z` is pushed, the Linux workflow should publish both:

- `Local-Qwen-Setup-X.Y.Z.run`
- `Local-Qwen-Setup-latest.run`

Recommended mental model for Ubuntu 24.04 install order:

1. Open TUI and collect desired settings
2. Bootstrap folders and state
3. Bootstrap package dependencies
4. Clone source repos
5. Install `OpenCode`
6. Download the default model through local `venv`
7. Write config and saved settings
8. Build upstream `llama.cpp`
9. Attempt `TurboQuant` CUDA build
10. Create launchers and desktop entries

Still being finalized:

- deeper distro coverage beyond Ubuntu 24.04
- end-to-end validation on a real clean Ubuntu 24.04 target
