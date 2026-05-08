# Installer status

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
- OpenCode config generation
- post-install verification script
- versioned `Inno Setup` packaging for `Local-Qwen-Setup-a.b.c.exe`
- repair/retry flow for partially completed `LocalQwenHome` installs

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

If a tag like `vX.Y.Z` is pushed, the workflow publishes `Local-Qwen-Setup-X.Y.Z.exe` to the GitHub release.

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
