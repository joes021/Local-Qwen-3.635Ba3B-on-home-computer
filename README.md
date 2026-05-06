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
- latest `llama.cpp` CUDA Windows binary download
- `TurboQuant` source clone for follow-up work
- recommended `Qwen 3.6 35B A3B` model download through `huggingface_hub`
- `OpenCode` install through `npm`
- automatic OpenCode config wiring to the local `llama.cpp` endpoint
- portable PowerShell launchers
- a GUI control center
- desktop shortcuts for the control center and OpenCode

## Quick start

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

### Linux

Run:

```bash
bash install/linux/install.sh
```

The Linux installer is still a public skeleton and is not yet at parity with the Windows milestone.
