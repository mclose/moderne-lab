#!/bin/bash
# Lab 2: open an interactive shell in the Moderne CLI container.
# ./ws on the host is /ws inside; repos.csv is at /lab/repos.csv.
# CLI, recipe JARs, and Maven/Gradle caches persist in the `moderne-lab-home` volume.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
docker image inspect moderne-lab-cli >/dev/null 2>&1 || docker build --build-arg LAB_UID="$(id -u)" --build-arg LAB_GID="$(id -g)" -t moderne-lab-cli "$HERE"
mkdir -p "$HERE/ws"
"$HERE/seed-demo.sh"
exec docker run --rm -it -u "$(id -u):$(id -g)" \
  -v "$HERE":/lab:ro -v "$HERE/ws":/ws -v moderne-lab-home:/home/lab \
  -w /ws moderne-lab-cli bash
