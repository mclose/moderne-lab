#!/bin/bash
# Lab 6: open a shell in the competitor sandbox (modernize + atx + gh + JDK 8/17/21 + Maven).
# ./ws on the host is /ws inside. gh/Copilot and atx state persist in the `moderne-lab-rivals-home` volume.
# AWS: pass credentials through the environment (AWS_PROFILE/AWS_ACCESS_KEY_ID/...), or keep ~/.aws on the host.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
docker image inspect moderne-lab-rivals >/dev/null 2>&1 || docker build --build-arg LAB_UID="$(id -u)" --build-arg LAB_GID="$(id -g)" -t moderne-lab-rivals "$HERE"
args=(-v "$HERE/ws":/ws -v moderne-lab-rivals-home:/home/lab -w /ws)
[ -d "$HOME/.aws" ] && args+=(-v "$HOME/.aws":/home/lab/.aws:ro)
for v in AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [ -n "${!v:-}" ] && args+=(-e "$v")
done
exec docker run --rm -it -u "$(id -u):$(id -g)" "${args[@]}" moderne-lab-rivals bash -c '
  git config --global user.name  >/dev/null || git config --global user.name  "lab6"
  git config --global user.email >/dev/null || git config --global user.email "lab6@localhost"
  git config --global --add safe.directory "*"
  exec bash'
