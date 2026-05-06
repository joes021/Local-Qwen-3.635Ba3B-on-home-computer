#!/usr/bin/env bash
set -euo pipefail

pkill -f 'llama-server' || true
echo "llama.cpp server stop requested."
