#!/bin/bash
# Slide demo (09-demo-slide.md): UpgradeToJava21 + UnpinnedActions on spring-petclinic-microservices.
#   ./demo.sh          clone twice, build, run, compare patches, apply on branch java21, rerun, verify, find unpinned actions
#   ./demo.sh reset    delete ws/demo (clones, patches, logs) so the next run starts clean
# Runs in the Lab 2 image at --cpus 1.5 and stops at the first failure. Logs land in ws/demo/logs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEMO="$HERE/ws/demo"
REPO=https://github.com/spring-petclinic/spring-petclinic-microservices
R21=org.openrewrite.java.migrate.UpgradeToJava21
PIN=org.openrewrite.github.security.UnpinnedActions
mod_in() {  # mod_in <dir under /ws/demo> <log name> <shell commands>
  docker run --rm --cpus 1.5 -u "$(id -u):$(id -g)" -v "$HERE/ws":/ws -v moderne-lab-home:/home/lab \
    -w "/ws/demo/$1" moderne-lab-cli bash -c "set -euxo pipefail; $3" > "$DEMO/logs/$2.log" 2>&1 \
    || { echo "FAILED: see $DEMO/logs/$2.log"; tail -20 "$DEMO/logs/$2.log"; exit 1; }
  grep -E 'MOD SUCCEEDED|✓ Maven|saved by|Produced results|MVNW_EXIT' "$DEMO/logs/$2.log" | grep -vE '^\s+0% ' || true
}
step() { echo; echo "######## $* ($(date +%T))"; }
newest_fix() { ls -td "$DEMO/$1"/spring-petclinic-microservices/.moderne/run/*/ | head -1; }

case "${1:-}" in
  reset) rm -rf "$DEMO" && echo "removed $DEMO"; exit 0 ;;
  "")    ;;
  *)     sed -n 2,5p "$0"; exit 1 ;;
esac
[ -e "$DEMO" ] && { echo "$DEMO exists; run ./demo.sh reset first"; exit 1; }
docker image inspect moderne-lab-cli >/dev/null 2>&1 || docker build --build-arg LAB_UID="$(id -u)" --build-arg LAB_GID="$(id -g)" -t moderne-lab-cli "$HERE"
mkdir -p "$DEMO/logs"

# The image has no recipe catalog; Lab 2 fills one in the moderne-lab-home volume. Install what the demo needs
# so it also runs on a machine that skipped Lab 2. Both runs below then use the same installed version.
step "recipes: rewrite-migrate-java"
mod_in "" recipes "mod config recipes jar install org.openrewrite.recipe:rewrite-migrate-java:RELEASE"

for r in run1 run2; do
  step "$r: clone, build, $R21"
  git clone -q "$REPO" "$DEMO/$r/spring-petclinic-microservices"
  git -C "$DEMO/$r/spring-petclinic-microservices" log -1 --format='main at %H (%cs)'
  mod_in "$r/spring-petclinic-microservices" "$r" "mod --version; mod build .; mod run . --recipe $R21"
  cp "$(newest_fix $r)fix.patch" "$DEMO/$r.patch"
done

step "determinism"
sha256sum "$DEMO/run1.patch" "$DEMO/run2.patch"
cmp "$DEMO/run1.patch" "$DEMO/run2.patch" && echo "patches identical"
grep -c '^diff --git' "$DEMO/run1.patch" | sed 's/$/ files changed/'

step "apply on branch java21, rebuild LST, rerun"
mod_in run1/spring-petclinic-microservices rerun \
  "git switch -c java21; mod git apply . --last-recipe-run; git diff --stat | tail -1; mod build .; mod run . --recipe $R21"
grep 'files changed' "$DEMO/logs/rerun.log"
d="$(newest_fix run1)"
if [ -s "${d}fix.patch" ]; then echo "rerun NOT empty: ${d}fix.patch"; exit 1; fi
echo "rerun produced no fix.patch (empty)"

step "./mvnw -q verify on JDK 21"
mod_in run1/spring-petclinic-microservices verify "git branch --show-current; java -version 2>&1 | head -1; ./mvnw -q verify; echo MVNW_EXIT=\$?"

step "$PIN on main (run2)"
mod_in run2/spring-petclinic-microservices unpinned \
  "mod config recipes jar install org.openrewrite.recipe:rewrite-github-actions:RELEASE; mod run . --recipe $PIN"
grep -E "Update\(|uses:|is not pinned" "$DEMO/logs/unpinned.log" | sed -E 's/^\s*[0-9]+% \([0-9ms ]+\)\s*//'
step done
