# Installer status

## Windows

The current Windows installer already scaffolds:

- install root
- state directory
- repo clones for `llama.cpp` and `TurboQuant`
- `OpenCode` global install through `npm`

Still being finalized:

- automatic model download
- portable runtime config generation
- desktop shortcuts
- final control center deployment

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
