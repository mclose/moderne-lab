#!/bin/bash
# Your-own-repo runs: shell in the CLI image + Python, capped at 1.5 CPUs (claude has 2).
# ./ws on the host is /ws inside. Shares the `moderne-lab-home` volume with Lab 2.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
docker image inspect moderne-lab-own >/dev/null 2>&1 || docker build -t moderne-lab-own "$HERE"
mkdir -p "$HERE/ws"
TTY=-i; [ -t 0 ] && TTY=-it
exec docker run --rm $TTY --cpus 1.5 -u 1001:1001 \
  -v "$HERE/ws":/ws -v moderne-lab-home:/home/lab \
  -w /ws moderne-lab-own "${@:-bash}"
