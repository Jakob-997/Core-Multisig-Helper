#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
shellcheck -x setup.sh lib/*.sh modules/*.sh tests/*.sh
for script in setup.sh lib/*.sh modules/*.sh tests/*.sh; do bash -n "$script"; done
bash tests/options.sh
python3 -m py_compile lib/*.py tests/*.py
python3 -m unittest discover -s tests -p 'test_*.py'
