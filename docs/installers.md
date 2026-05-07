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

Still being finalized:

- more robust CUDA/toolchain auto-recovery when build prerequisites are missing
- hardware-aware fallback logic for more GPUs
- fuller verification pipeline after install

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
- `start-opencode.sh`
- desktop launcher files
- post-install verification script
- runtime build through `launcher/linux/build-runtime.sh`
- Ubuntu 24.04-oriented package bootstrap
- self-extract `.run` packaging through `packaging/linux/build-run-installer.sh`

Still being finalized:

- deeper distro coverage beyond Ubuntu 24.04
- end-to-end validation on a real clean Ubuntu 24.04 target
