#!/bin/bash
# Lab 6 scorecard: compare each petclinic-* copy against the Boot 2.7 baseline (1db99db).
#   ./score.sh            static facts only (fast)
#   ./score.sh --test     also run `mvn verify` on Java 17 for each (about 1-2 min each)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="$(cd "$HERE/.." && pwd)"
mkdir -p "$LAB/.m2"
BASE=1db99db
for d in "$HERE"/ws/petclinic-*; do
  t="${d##*-}"
  git -C "$d" add -A >/dev/null 2>&1   # count uncommitted work too
  boot=$(grep -A1 '<artifactId>spring-boot-starter-parent' "$d/pom.xml" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^<]*' | head -1)
  java=$(grep -oE '<java.version>[^<]+' "$d/pom.xml" | cut -d'>' -f2)
  javax=$(grep -rE 'import javax\.(persistence|validation|servlet)' "$d/src" 2>/dev/null | wc -l)
  stat=$(git -C "$d" diff --cached --shortstat "$BASE" | sed 's/ changed//; s/insertions*(+)/+/; s/deletions*(-)/-/')
  commits=$(git -C "$d" rev-list --count "$BASE"..HEAD)
  printf '%-12s boot=%-8s java=%-4s javax-imports-left=%-3s commits=%-3s %s\n' "$t" "$boot" "$java" "$javax" "$commits" "$stat"
  git -C "$d" reset -q
done
if [ "${1:-}" = "--test" ]; then
  for d in "$HERE"/ws/petclinic-*; do
    t="${d##*-}"
    res=$(docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e MAVEN_CONFIG=/tmp/.m2 -e MAVEN_OPTS=-Duser.home=/tmp \
      -v "$LAB/.m2":/m2 -v "$d":/src -w /src maven:3.9-eclipse-temurin-17 \
      mvn -B -Dmaven.repo.local=/m2/repository -Dspring-javaformat.skip=true -Dcheckstyle.skip=true verify 2>&1 \
      | grep -E '^\[(INFO|WARNING|ERROR)\] Tests run:.*Skipped: [0-9]+$|BUILD (SUCCESS|FAILURE)' | tail -2 | tr '\n' ' ')
    printf '%-12s %s\n' "$t" "$res"
  done
fi
