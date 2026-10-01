#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
shellcheck setup.sh
bash -n setup.sh
python3 -m py_compile wallets.py tests/integration.py
