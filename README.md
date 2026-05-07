# Local Qwen 3.635Ba3B on home computer

One-click local AI setup for home computers with:

- `llama.cpp`
- `TurboQuant`
- a GPU-fit `Qwen 3.6 35B A3B` model profile
- `OpenCode` wired to the local model
- a local control center for launch, tuning, and agent modes
- Windows and Linux installers

## Goal

This project aims to make local `Qwen 3.6 35B A3B` usable on a normal home computer with as little manual setup as possible.

The target experience is:

1. Run one installer
2. Let it detect the machine
3. Download and configure the right local stack
4. Get one or two desktop launchers that do the real work

## Planned features

- Windows all-in-one installer
- Linux all-in-one installer
- Hardware-aware model/profile selection
- `OpenCode` auto-configuration
- local GUI control center
- safe agent modes with selectable working directory

## Status

This repository is being built from a real working local setup and is currently in the first public packaging phase.

## Current Windows milestone

The first usable Windows milestone now includes:

- dependency bootstrap through `winget`
- `Visual Studio Build Tools 2022` and `CUDA Toolkit` bootstrap attempts
- latest `llama.cpp` CUDA Windows binary download
- `TurboQuant` source clone and build script
- recommended `Qwen 3.6 35B A3B` model download through `huggingface_hub`
- `OpenCode` install through `npm`
- automatic OpenCode config wiring to the local `llama.cpp` endpoint during install
- portable PowerShell launchers
- a GUI control center
- desktop shortcuts for the control center and OpenCode

## Quick start

### Windows release installer

The repo can now produce a versioned Windows installer:

`Local-Qwen-Setup-a.b.c.exe`

Build it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-setup.ps1
```

If `Inno Setup 6` is installed, the setup file will be created under:

`dist\windows\`

GitHub Actions can also build and publish the same installer:

- manual workflow run: `windows-setup`
- tag release flow: push tag `vX.Y.Z`

### Ubuntu 24.04 release installer

The repo can now also produce a self-extract Linux installer aimed at `Ubuntu 24.04`:

`Local-Qwen-Setup-a.b.c.run`

Build it with:

```bash
bash ./packaging/linux/build-run-installer.sh
```

Run it on Ubuntu 24.04 with:

```bash
chmod +x ./Local-Qwen-Setup-a.b.c.run
./Local-Qwen-Setup-a.b.c.run
```

GitHub Actions can also build and publish the same `.run` release asset:

- manual workflow run: `linux-run-setup`
- tag release flow: push tag `vX.Y.Z`

### Windows

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1
```

After install, open the desktop folder:

`Local Qwen Home Computer`

Then launch:

- `Local Qwen Control Center`
- `OpenCode - Local Qwen`
- `Verify Local Qwen Install`

Optional manual verify:

```powershell
powershell -ExecutionPolicy Bypass -File .\launcher\windows\verify-install.ps1
```

### Linux

Run:

```bash
bash install/linux/install.sh
```

The Linux installer is now oriented toward `Ubuntu 24.04` and is no longer just a skeleton.

It now also includes:

- local launcher deployment
- runtime build step for upstream `llama.cpp`
- best-effort `TurboQuant` CUDA build when `nvcc` is available
- OpenCode config writer
- terminal control center
- `start-opencode.sh` helper
- `verify-install.sh`

Optional manual verify:

```bash
bash launcher/linux/verify-install.sh
```
