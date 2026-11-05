#!/bin/bash
# Lab 4: dependency-CVE scan + fix on the AI-found-CVE demo repo, with the free OpenRewrite Maven plugin.
# (The Moderne CLI refuses this repo: it's not a public open-source repo, so it needs a license.)
#   ./lab4.sh scan     find vulnerable deps, print the report, write target/rewrite/rewrite.patch (changes nothing)
#   ./lab4.sh fix      apply the scanner's own upgrades to pom.xml
#   ./lab4.sh jetty    apply the hand-written CVE-2026-19204 recipe (lab/recipes) for the gap the scanner missed
#   ./lab4.sh reset    put the demo repo back to its committed state
set -euo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
DEMO="$LAB/cli/ws/local/ai-found-cves"
"$LAB/cli/seed-demo.sh"
mkdir -p "$LAB/.m2"
SEC=org.openrewrite.recipe:rewrite-java-security:3.38.1
mvn() {
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e MAVEN_CONFIG=/tmp/.m2 -e MAVEN_OPTS=-Duser.home=/tmp \
    -v "$LAB/.m2":/m2 -v "$DEMO":/src -w /src maven:3.9-eclipse-temurin-17 \
    mvn -B -Dmaven.repo.local=/m2/repository "$@" 2>&1 | grep -E '^\[(WARNING|ERROR)\]|BUILD'
}
plugin() { mvn org.openrewrite.maven:rewrite-maven-plugin:6.46.1:"$1" -Drewrite.recipeArtifactCoordinates="$2" -Drewrite.activeRecipes="$3" -Drewrite.exportDatatables=true; }
report() {
  f=$(ls -t "$DEMO"/target/rewrite/datatables/*/*VulnerabilityReport.csv 2>/dev/null | head -1) || true
  [ -n "$f" ] || { echo "no report"; return; }
  echo; echo "== Vulnerability report ($(( $(grep -vc "^#" "$f") - 1 )) rows): $f"
  python3 -I - "$f" <<'PY'
import csv, sys
rows = [r for r in csv.DictReader(l for l in open(sys.argv[1]) if not l.startswith("#"))]
print(f"{'CVE':18} {'artifact':45} {'have':8} {'fixed':8} {'sev':8} depth")
for r in rows:
    print(f"{r['cve']:18} {r['groupId']+':'+r['artifactId']:45} {r['version']:8} {r['fixedVersion']:8} {r['severity']:8} {r['depth']}")
PY
}
case "${1:-}" in
  scan)  rm -rf "$DEMO/target"; plugin dryRun "$SEC" org.openrewrite.java.dependencies.DependencyVulnerabilityCheck; report
         echo; echo "== Proposed patch:"; cat "$DEMO/target/rewrite/rewrite.patch" 2>/dev/null || echo "(none)" ;;
  fix)   plugin run "$SEC" org.openrewrite.java.dependencies.DependencyVulnerabilityCheck; git -C "$DEMO" diff ;;
  jetty) "$LAB/recipes/mvn.sh" -q install -DskipTests >/dev/null
         plugin run lab:security-recipes:0.1.0-SNAPSHOT lab.security.JettyCve202619204; git -C "$DEMO" diff ;;
  reset) git -C "$DEMO" checkout -q -- . && rm -rf "$DEMO/target" && git -C "$DEMO" status --short && echo "demo repo reset" ;;
  *)     sed -n 2,8p "$0"; exit 1 ;;
esac
