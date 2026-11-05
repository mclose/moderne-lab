#!/bin/bash
# Run recipes from this project (must be ./mvn.sh install-ed first) against the Lab 4 demo repo.
#   ./run-on-demo.sh dryRun lab.security.FindUnsafeRarExtraction[,other.Recipe]
#   ./run-on-demo.sh run    lab.security.JettyCve202619204
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="$(cd "$HERE/.." && pwd)"
DEMO="$LAB/cli/ws/local/ai-found-cves"
"$LAB/cli/seed-demo.sh"
GOAL="${1:?dryRun or run}"; RECIPES="${2:?recipe name(s), comma-separated}"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e MAVEN_CONFIG=/tmp/.m2 -e MAVEN_OPTS=-Duser.home=/tmp \
  -v "$LAB/.m2":/m2 -v "$DEMO":/src -w /src maven:3.9-eclipse-temurin-17 \
  mvn -B -Dmaven.repo.local=/m2/repository org.openrewrite.maven:rewrite-maven-plugin:6.46.1:"$GOAL" \
  -Drewrite.recipeArtifactCoordinates=lab:security-recipes:0.1.0-SNAPSHOT \
  -Drewrite.activeRecipes="$RECIPES" 2>&1 | grep -E 'WARN|ERROR|BUILD'
[ "$GOAL" = dryRun ] && [ -f "$DEMO/target/rewrite/rewrite.patch" ] && cat "$DEMO/target/rewrite/rewrite.patch"
true
