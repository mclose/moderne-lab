#!/bin/bash
# Run Maven for this recipe project in Docker (JDK 21). No Java on the host.
#   ./mvn.sh test       run recipe tests
#   ./mvn.sh install    build + install lab:security-recipes:0.1.0-SNAPSHOT into lab/.m2
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="$(cd "$HERE/.." && pwd)"
mkdir -p "$LAB/.m2"
exec docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e MAVEN_CONFIG=/tmp/.m2 -e MAVEN_OPTS=-Duser.home=/tmp \
  -v "$LAB/.m2":/m2 -v "$HERE":/src -w /src maven:3.9-eclipse-temurin-21 \
  mvn -B -Dmaven.repo.local=/m2/repository "$@"
