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

If a tag like `v1.0.0` is pushed, the workflow publishes `Local-Qwen-Setup-1.0.0.exe` to the GitHub release.

## Linux

The current Linux installer is still below Windows parity, but it is no longer just a placeholder.

It currently handles:

- install root creation
- repo clone for `llama.cpp` and `TurboQuant`
- `OpenCode` install via `npm`
- install state output
- launcher deployment
- OpenCode config writer
- terminal control center
- `start-opencode.sh`
- desktop launcher files
- post-install verification script

Still being finalized:

- distro-aware dependency install
- full build pipeline automation
- desktop integration
- end-to-end validation on a real Linux target
