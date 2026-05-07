# Local Qwen 3.635Ba3B on home computer

> One-click local AI setup for a strong home PC.

[![Windows Setup](https://img.shields.io/badge/Windows-Setup.exe-0078D6?logo=windows&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.2.1)
[![Ubuntu 24.04 Setup](https://img.shields.io/badge/Ubuntu%2024.04-Setup.run-E95420?logo=ubuntu&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.2.1)
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

## What You Get

- local `llama.cpp` runtime
- `TurboQuant` source and build flow
- recommended `Qwen 3.6 35B A3B` GGUF profile
- `OpenCode` wired to the local model
- desktop launchers
- local control center
- configurable context, output, and agent-step tuning

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

2. Download:

`Local-Qwen-Setup-1.2.1.exe`

3. Run the installer.

### Ubuntu 24.04

1. Open the latest release:

[Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)

2. Download:

`Local-Qwen-Setup-1.2.1.run`

3. Run:

```bash
chmod +x ./Local-Qwen-Setup-1.2.1.run
./Local-Qwen-Setup-1.2.1.run
```

Or directly from terminal:

```bash
wget https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.2.1/Local-Qwen-Setup-1.2.1.run
chmod +x ./Local-Qwen-Setup-1.2.1.run
./Local-Qwen-Setup-1.2.1.run
```

## How To Start After Install

### Windows

After install, open the desktop folder:

`Local Qwen Home Computer`

Main things you can start:

- `Local Qwen Control Center`
- `OpenCode - Local Qwen`
- `Verify Local Qwen Install`

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

What they do:

- `control-center.sh` opens the main Linux TUI menu
- `start-opencode.sh` starts the local server if needed and then opens `OpenCode`
- `start-server.sh` starts only the `llama.cpp` server
- `settings-tui.sh` changes saved settings without reinstalling

## Current Release

Current public release:

- [Local Qwen Setup 1.2.1](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.2.1)
- [Windows installer](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.2.1/Local-Qwen-Setup-1.2.1.exe)
- [Ubuntu 24.04 installer](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.2.1/Local-Qwen-Setup-1.2.1.run)

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
- [Design notes](./docs/superpowers/specs/2026-05-07-local-qwen-home-computer-design.md)

## Feedback

If something breaks on a clean machine, open an issue with:

- OS version
- GPU
- RAM
- full installer log
- where it stopped
