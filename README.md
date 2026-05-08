# Local Qwen 3.635Ba3B on home computer

> One-click local AI setup for a strong home PC.

[![Windows Setup](https://img.shields.io/badge/Windows-Releases-0078D6?logo=windows&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest)
[![Ubuntu 24.04 Setup](https://img.shields.io/badge/Ubuntu%2024.04-Releases-E95420?logo=ubuntu&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest)
[![Release](https://img.shields.io/github/v/release/joes021/Local-Qwen-3.635Ba3B-on-home-computer)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)
[![Repo](https://img.shields.io/badge/GitHub-public%20repo-181717?logo=github)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer)

This project packages a real working local setup around:

- `llama.cpp`
- `TurboQuant`
- `Qwen 3.6 35B A3B`
- `OpenCode`
- local launchers and a control center

The goal is simple:

1. Download one installer
2. Run it on your machine
3. Let it prepare the local stack
4. Get 1-2 launchers that are actually useful

## Versioning Policy

Windows and Linux always share the same release number.

- one shared `version.json` is the single source of truth
- every public release publishes both a Windows and a Linux installer with that same version
- a fix can be Windows-only or Linux-only in code
- even then, the public release number stays aligned across both platforms
- every tag now also runs a release verifier workflow that fails if one of the two platform installers is missing

## What It Does

After install, this setup:

- installs or prepares the local `llama.cpp` runtime
- prepares `TurboQuant`
- downloads a local `Qwen 3.6 35B A3B` GGUF profile
- wires `OpenCode` to the local `llama.cpp` server
- saves local settings for:
  - profile
  - context size
  - max output tokens
  - OpenCode step limits
  - working directory
- gives you launchers for:
  - starting the model server
  - starting OpenCode
  - changing settings later
  - verifying the install
- gives Windows a unified Control Center with tabs for:
  - `Pokretanje`
  - `Podesavanja`
  - `Agent`

## What You Get

- local `llama.cpp` runtime
- `TurboQuant` source and build flow
- recommended `Qwen 3.6 35B A3B` GGUF profile
- `OpenCode` wired to the local model
- desktop launchers
- local control center
- configurable context, output, and agent-step tuning
- shared hardware recommendation engine for Windows and Linux
- multi-model catalog with compact and quality quant choices
- diagnostics export and update-check helpers

## Install Order

### Windows install order

When you run the Windows installer, it goes roughly in this order:

1. Creates the install folders and state directories
2. Checks or installs:
   - `git`
   - `node`
   - `npm`
   - `python`
   - `cmake`
   - `ninja`
3. Checks or installs:
   - `Visual Studio Build Tools 2022`
   - `CUDA Toolkit`
4. Clones:
   - upstream `llama.cpp`
   - `llama.cpp-turboquant`
5. Downloads upstream `llama.cpp` CUDA Windows binaries
6. Installs `OpenCode`
7. Downloads the default GGUF model
8. Copies launchers, config, and icons into the local install root
9. Writes the local install state and saved settings
10. Writes the `OpenCode` config pointing to the local `llama.cpp` endpoint
11. Builds `TurboQuant` if build prerequisites are available
12. Creates desktop shortcuts

### Ubuntu 24.04 install order

When you run the Linux `.run` installer, it goes roughly in this order:

1. Opens the interactive `TUI` installer
2. Collects your chosen settings:
   - profile
   - context size
   - max output tokens
   - OpenCode steps
   - working directory
3. Creates the install folders and state directories
4. Checks or installs:
   - `git`
   - `curl`
   - `python3`
   - `python3-pip`
   - `python3-venv`
   - `node`
   - `npm`
   - `cmake`
   - `ninja`
   - `build-essential`
5. On Ubuntu 24.04, also tries to install:
   - `libcurl4-openssl-dev`
   - `libopenblas-dev`
   - `nvidia-cuda-toolkit`
6. Clones:
   - upstream `llama.cpp`
   - `llama.cpp-turboquant`
7. Installs `OpenCode`
8. Downloads the default GGUF model through a local Python `venv`
9. Writes the local install state and saved settings
10. Writes the `OpenCode` config pointing to the local `llama.cpp` endpoint
11. Builds upstream `llama.cpp`
12. Tries a `TurboQuant` CUDA build if `nvcc` is available
13. Creates desktop launchers and local TUI launchers

## Quick Start

### Windows

1. Open the latest release:

[Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)

2. Download the stable latest Windows installer:

[Local-Qwen-Setup-latest.exe](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.exe)

3. Run the installer.

If a previous Windows install stopped halfway, rerunning the latest Windows `Setup.exe` is the supported repair path. The installer now restores the local launcher/config layout early and can continue from a partial `LocalQwenHome` state instead of requiring manual file copies.

### Ubuntu 24.04

1. Open the latest release:

[Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)

2. Download the stable latest Ubuntu 24.04 installer:

[Local-Qwen-Setup-latest.run](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.run)

3. Run:

```bash
chmod +x ./Local-Qwen-Setup-latest.run
./Local-Qwen-Setup-latest.run
```

Or directly from terminal:

```bash
wget -O Local-Qwen-Setup-latest.run https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.run
chmod +x ./Local-Qwen-Setup-latest.run
./Local-Qwen-Setup-latest.run
```

## How To Start After Install

### Windows

After install, open the desktop folder:

`Local Qwen Home Computer`

Main things you can start:

- `Local Qwen Control Center`
- `OpenCode - Local Qwen`
- `Verify Local Qwen Install`
- `Repair Windows App Control`

The Windows `Local Qwen Control Center` now includes:

- `Pokretanje`: `Start balanced`, `Start video`, `Start speed`, `Stop server`, `Otvori OpenCode`, `Otvori llama.cpp web`, `Osvezi status`, `Otvori folder`
- `Pokretanje`: `Repair install`, `Test prompt`, `Model manager`, `Diagnostics`, `Check updates`
- `Podesavanja`: `model variant`, `context size`, `max output tokens`, `build steps`, `plan steps`, `general steps`, `explore steps`
- `Agent`: security mode, autonomy mode, working folder, save and launch actions
- `Logovi`: latest `stdout`, `stderr`, `install summary`, `install report`

### Ubuntu 24.04

After install, the main commands are:

```bash
/home/$USER/local-qwen-home/launchers/control-center.sh
```

```bash
/home/$USER/local-qwen-home/launchers/start-opencode.sh
```

```bash
/home/$USER/local-qwen-home/launchers/start-server.sh
```

```bash
/home/$USER/local-qwen-home/launchers/settings-tui.sh
```

```bash
/home/$USER/local-qwen-home/launchers/manage-models.sh
```

```bash
/home/$USER/local-qwen-home/launchers/export-diagnostics.sh
```

```bash
/home/$USER/local-qwen-home/launchers/check-updates.sh
```

What they do:

- `control-center.sh` opens the main Linux TUI menu
- `start-opencode.sh` starts the local server if needed and then opens `OpenCode`
- `start-server.sh` starts only the `llama.cpp` server
- `settings-tui.sh` changes saved settings without reinstalling
- `manage-models.sh` prikazuje katalog modela i moze da aktivira preporuceni ili zadati model
- `show-logs.sh` prints the newest runtime and install logs in one place
- `repair-install.sh` refreshes key install pieces and rewrites reports/config
- `test-prompt.sh` sends a tiny smoke-test prompt to the local model
- `export-diagnostics.sh` pravi jedan arhivirani bundle za debug
- `check-updates.sh` proverava da li na GitHub-u postoji noviji release

## Windows App Control / Smart App Control edge case

Some Windows 11 machines can block `llama-server.exe` even when the install completed correctly. The most common reason is `Smart App Control`, which appears in `CiTool.exe -lp` as:

- `VerifiedAndReputableDesktop`

Symptoms:

- desktop launchers appear normally
- `verify-install` finds files, but launching `llama.cpp` fails
- the error mentions `Application Control policy has blocked this file`

The Windows installer now also places a desktop shortcut for this exact case:

- `Repair Windows App Control`

You can diagnose and attempt to fix that case with:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\LocalQwenHome\launchers\repair-app-control.ps1"
```

To attempt turning Smart App Control off from an elevated PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\LocalQwenHome\launchers\repair-app-control.ps1" -DisableSmartAppControl
```

Important:

- this requires administrator rights
- if the machine is organization-managed, policy can return
- Microsoft documents that turning Smart App Control off can be a one-way action on some systems

## Current Release

Current public releases:

- [Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)
- [Latest Release Page](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest)
- [Stable latest Windows setup](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.exe)
- [Stable latest Ubuntu setup](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/latest/download/Local-Qwen-Setup-latest.run)

Release integrity rule:

- a release is considered healthy only when all 4 public assets exist:
  - `Local-Qwen-Setup-X.Y.Z.exe`
  - `Local-Qwen-Setup-latest.exe`
  - `Local-Qwen-Setup-X.Y.Z.run`
  - `Local-Qwen-Setup-latest.run`
- GitHub Actions now verifies that set automatically on every release tag

## Windows Installer Notes

The current Windows setup includes:

- dependency bootstrap through `winget`
- `Visual Studio Build Tools 2022`
- `CUDA Toolkit`
- latest upstream `llama.cpp` CUDA Windows binary download
- `TurboQuant` source clone and build flow
- recommended model download via `huggingface_hub`
- `OpenCode` install through `npm`
- automatic local endpoint wiring
- desktop shortcuts and control center

## Ubuntu 24.04 Notes

The current Linux setup is focused on `Ubuntu 24.04`.

It currently includes:

- dependency bootstrap for Ubuntu-style systems
- interactive terminal installer (`TUI`) for Ubuntu 24.04
- local launcher deployment
- upstream `llama.cpp` runtime build
- best-effort `TurboQuant` CUDA build when `nvcc` is available
- public IQ2_M GGUF source for the default 12 GB class profile
- local `OpenCode` configuration
- richer terminal control center with saved settings
- separate `settings-tui.sh` for post-install reconfiguration
- post-install verification helper

## Manual Source Install

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1
```

### Linux

```bash
bash install/linux/install.sh
```

## Build Release Packages

### Windows release package

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-setup.ps1
```

### Linux release package

```bash
bash ./packaging/linux/build-run-installer.sh
```

### One-command cross-platform release

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\release-all.ps1
```

## Repo Layout

- `install/` installer entry points
- `launcher/` local launchers and control flows
- `packaging/` release packaging
- `config/` default profiles
- `assets/` icons
- `docs/` implementation notes and installer status

## Status

This repo is public and usable, but still evolving.

Most mature path today:

- `Windows Setup.exe`
- `Ubuntu 24.04 Setup.run`

The Linux path is public and packaged, but still needs more real-world validation on clean machines.

## Documentation

- [Installer status](./docs/installers.md)
- [Roadmap](./docs/roadmap.md)
- [Design notes](./docs/superpowers/specs/2026-05-07-local-qwen-home-computer-design.md)

## Feedback

If something breaks on a clean machine, open an issue with:

- OS version
- GPU
- RAM
- full installer log
- where it stopped
