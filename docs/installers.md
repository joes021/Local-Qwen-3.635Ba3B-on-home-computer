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

Still being finalized:

- more robust CUDA/toolchain auto-recovery when build prerequisites are missing
- hardware-aware fallback logic for more GPUs
- fuller verification pipeline after install

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

Still being finalized:

- distro-aware dependency install
- full build pipeline automation
- desktop integration
- end-to-end validation on a real Linux target
