# Installer status

## Windows

The current Windows installer now handles:

- install root
- state directory
- latest upstream `llama.cpp` CUDA Windows release download
- `TurboQuant` source clone
- recommended model download through Python + `huggingface_hub`
- `OpenCode` global install through `npm`
- launcher deployment
- icon deployment
- desktop shortcut creation
- OpenCode config generation

Still being finalized:

- automatic `TurboQuant` Windows build
- hardware-aware fallback logic for more GPUs
- fuller verification pipeline after install

## Linux

The current Linux installer is a first public skeleton.

It currently handles:

- install root creation
- repo clone for `llama.cpp` and `TurboQuant`
- `OpenCode` install via `npm`
- install state output

Still being finalized:

- distro-aware dependency install
- build pipeline automation
- launcher deployment
- desktop integration
