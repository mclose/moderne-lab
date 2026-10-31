#!/bin/bash
# Lab 1: OpenRewrite on one repo, no accounts. Everything runs in Docker (no host Java).
#   ./lab1.sh reset    put petclinic back at Spring Boot 2.7 / Java 8 (commit 1db99db)
#   ./lab1.sh dryrun   compute the migration, write target/rewrite/rewrite.patch, change nothing
#   ./lab1.sh run      apply the migration to the working tree
#   ./lab1.sh test     compile + run the test suite on Java 17
#   ./lab1.sh mvn ...  any other maven command
set -euo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
REPO="$LAB/spring-petclinic"
PLUGIN=org.openrewrite.maven:rewrite-maven-plugin:6.46.1
RECIPES=org.openrewrite.recipe:rewrite-spring:6.37.1
RECIPE="${RECIPE:-org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_5}"

mvn() {
  mkdir -p "$LAB/.m2"
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e MAVEN_CONFIG=/tmp/.m2 -e MAVEN_OPTS=-Duser.home=/tmp \
    -v "$LAB/.m2":/m2 -v "$REPO":/src -w /src maven:3.9-eclipse-temurin-17 \
    mvn -B -Dmaven.repo.local=/m2/repository -Dspring-javaformat.skip=true -Dcheckstyle.skip=true "$@"
}
rewrite() {
  mvn "$PLUGIN:$1" -Drewrite.recipeArtifactCoordinates="$RECIPES" -Drewrite.activeRecipes="$RECIPE"
}

[ -d "$REPO" ] || git clone -q https://github.com/spring-projects/spring-petclinic.git "$REPO"
case "${1:-}" in
  reset)  git -C "$REPO" reset -q --hard && git -C "$REPO" clean -qfdx && git -C "$REPO" checkout -q 1db99db
          echo "petclinic at $(git -C "$REPO" log -1 --format='%h %s')" ;;
  dryrun) rewrite dryRun 2>&1 | grep -vE 'Download(ing|ed) from'
          echo; echo "Patch: $REPO/target/rewrite/rewrite.patch" ;;
  run)    rewrite run 2>&1 | grep -vE 'Download(ing|ed) from' | tail -15
          git -C "$REPO" status --short ;;
  test)   mvn verify 2>&1 | grep -E 'Tests run:|ERROR|BUILD|Total time' ;;
  mvn)    shift; mvn "$@" ;;
  *)      sed -n 2,7p "$0"; exit 1 ;;
esac
