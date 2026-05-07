# Local Qwen 3.635Ba3B on home computer

> One-click local AI setup for a strong home PC.

[![Windows Setup](https://img.shields.io/badge/Windows-Setup.exe-0078D6?logo=windows&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.1.2)
[![Ubuntu 24.04 Setup](https://img.shields.io/badge/Ubuntu%2024.04-Setup.run-E95420?logo=ubuntu&logoColor=white)](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.1.2)
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

## What You Get

- local `llama.cpp` runtime
- `TurboQuant` source and build flow
- recommended `Qwen 3.6 35B A3B` GGUF profile
- `OpenCode` wired to the local model
- desktop launchers
- local control center
- configurable context, output, and agent-step tuning

## Quick Start

### Windows

1. Open the latest release:

[Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)

2. Download:

`Local-Qwen-Setup-1.1.2.exe`

3. Run the installer.

### Ubuntu 24.04

1. Open the latest release:

[Latest Releases](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases)

2. Download:

`Local-Qwen-Setup-1.1.2.run`

3. Run:

```bash
chmod +x ./Local-Qwen-Setup-1.1.2.run
./Local-Qwen-Setup-1.1.2.run
```

Or directly from terminal:

```bash
wget https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.1.2/Local-Qwen-Setup-1.1.2.run
chmod +x ./Local-Qwen-Setup-1.1.2.run
./Local-Qwen-Setup-1.1.2.run
```

## Current Release

Current public release:

- [Local Qwen Setup 1.1.2](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/tag/v1.1.2)
- [Windows installer](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.1.2/Local-Qwen-Setup-1.1.2.exe)
- [Ubuntu 24.04 installer](https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer/releases/download/v1.1.2/Local-Qwen-Setup-1.1.2.run)

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
- local launcher deployment
- upstream `llama.cpp` runtime build
- best-effort `TurboQuant` CUDA build when `nvcc` is available
- public IQ2_M GGUF source for the default 12 GB class profile
- local `OpenCode` configuration
- terminal control center
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
