#!/bin/bash
# Lab 8b: a scanner report on a small app with real holes; agents vs. one recipe, judged by live exploits.
#   ./ab2.sh setup             5 identical clones of ./ledger (fixed commit dates -> same hashes)
#   ./ab2.sh baseline          verify + exploit probes on the untouched app
#   ./ab2.sh recipe [N...]     Side B: lab.LedgerScannerFindings via the OpenRewrite Maven plugin; hash the patches
#   ./ab2.sh agent [N...]      Side A: one fresh Copilot session per clone; MODEL=..., optional TAG=...
#   ./ab2.sh panel [N...]      the same prompt on PANEL="m1 m2 ..." models, in rounds; VARIANT=start|named|lookpast (see below)
#   ./ab2.sh crosscheck        run the recipe (dry run) on every agent result: what would it still change?
#   ./ab2.sh status            what's done so far
#   ./ab2.sh reset [--dry-run] delete ws/ and results/
# Why the Maven plugin, not mod: the Moderne CLI only runs recipes on public open-source repos without a
# license ("this repository is not an open source repository"). The plugin is free and runs the same recipes.
# Every result gets: ./mvnw clean verify, then the app jar is started in a --network none container and
# attacked by probe/Probe.java (outside the repo, so no agent can fix to the test).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HERE/ws" OUT="$HERE/results" SRC="$HERE/ledger"
RECIPE=lab.LedgerScannerFindings
PLUGIN=org.openrewrite.maven:rewrite-maven-plugin:6.46.1
RECIPE_JARS=org.openrewrite.recipe:rewrite-java-security:3.38.1,org.openrewrite.recipe:rewrite-java-dependencies:1.60.2
TOKEN_FILE="${COPILOT_TOKEN_FILE:-$HOME/.config/moderne-lab/copilot.token}"
LABEL=course=moderne-lab
CLONES=(1 2 3 4 5)
PANEL_DEFAULT="gpt-5.3-codex grok-4.7 gemini-3.8-flash"
read -r -d '' PROMPT <<'EOF' || true
Our security scanner (weekly SCA + SAST run) reported these findings for this repo. Fix them so the build still passes.

1. CRITICAL  CVE-2022-42889 (Text4Shell)  org.apache.commons:commons-text 1.9  ledger-common/pom.xml:17
2. HIGH      CVE-2022-33980  org.apache.commons:commons-configuration2 2.7  pom.xml:30 (also brings commons-text 1.8 into ledger-accounts)
3. HIGH      CWE-611 XML External Entity (XXE) injection  ledger-statements/src/main/java/com/example/ledger/statements/StatementImporter.java:33
4. HIGH      CWE-22 Path traversal in archive extraction (Zip Slip)  ledger-reports/src/main/java/com/example/ledger/reports/ReportArchiveService.java:34
5. HIGH      CWE-89 SQL injection  ledger-accounts/src/main/java/com/example/ledger/accounts/AccountRepository.java:36
EOF
# Variants, each tagged <variant>-<model>. All three add the start-the-app line.
#   start     the same ticket
#   named     the ticket also lists the three holes it left out (the canary: can agents fix them when told?)
#   lookpast  the same ticket plus one line asking the agent to look for other instances of the same problems
START=$'\n\nBefore you finish, build the app jar (ledger-app) and start it to confirm it actually runs.'
case "${VARIANT:-}" in
  "") ;;
  start) PROMPT+=$START ;;
  named) PROMPT+=$'\n6. HIGH      CWE-611 XML External Entity (XXE) injection  ledger-reports/src/main/java/com/example/ledger/reports/ReportMetadataReader.java:18'
         PROMPT+=$'\n7. HIGH      CWE-611 XML External Entity (XXE) injection  ledger-accounts/src/main/java/com/example/ledger/accounts/AccountListImporter.java:23'
         PROMPT+=$'\n8. HIGH      CWE-89 SQL injection  ledger-accounts/src/main/java/com/example/ledger/accounts/AccountRepository.java:42'
         PROMPT+=$START ;;
  lookpast) PROMPT+=$'\n\nThe scanner may have missed other instances of these same problems. Check the rest of the code for them and fix those too.'
            PROMPT+=$START ;;
  *) echo "ERROR: VARIANT must be empty, 'start', 'named' or 'lookpast'" >&2; exit 1 ;;
esac

step() { echo; echo "######## $* ($(date +%T))"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
clone_dir() { echo "$WS/clone$1"; }
pick() { [ $# -gt 0 ] && echo "$@" || echo "${CLONES[@]}"; }
valid_n() { for n in "$@"; do [[ "$n" =~ ^[1-5]$ ]] || die "clone number must be 1-5, got '$n'"; done; }
need_agent() { docker image inspect moderne-lab-agent >/dev/null 2>&1 \
                 || docker build --label "$LABEL" -t moderne-lab-agent -f "$HERE/../ab/Dockerfile.agent" "$HERE/../ab"; }
mvn_in() {  # mvn_in <clone n> <log> <commands>: dev container with network (Maven Central) and the shared cache
  need_agent
  docker run --rm --cpus 1.5 --label "$LABEL" -v "$WS":/ws -v "$HERE":/lab:ro -v moderne-lab-ab-m2:/home/lab/.m2 \
    -w "/ws/clone$1" moderne-lab-agent bash -c "$3" > "$OUT/logs/$2.log" 2>&1
}

# check <clone n> <name>: clean verify, then build the jar (even if tests fail) and run the exploit probes offline.
check() {
  local n=$1 name=$2
  if mvn_in "$n" "$name-verify" './mvnw -q clean verify'; then echo PASS > "$OUT/$name.verify"; else echo FAIL > "$OUT/$name.verify"; fi
  [ -f "$(clone_dir "$n")/ledger-app/target/ledger-app.jar" ] || mvn_in "$n" "$name-package" './mvnw -q -DskipTests clean package' || true
  docker run --rm --network none --cpus 1 --label "$LABEL" -v "$HERE/probe":/probe:ro -v "$(clone_dir "$n")":/app:ro \
    -v "$OUT":/out moderne-lab-agent /probe/run-probe.sh /app/ledger-app/target/ledger-app.jar "/out/$name.probe.jsonl" \
    > "$OUT/logs/$name-probe.log" 2>&1 || echo "probe error (logs/$name-probe.log)"
  printf '%s verify=%s  ' "$name" "$(cat "$OUT/$name.verify")"
  python3 -I -c 'import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
print(" ".join("%s=%s" % (x["id"], x["verdict"]) for x in r))' "$OUT/$name.probe.jsonl" 2>/dev/null || echo "(no probe results)"
}

clean_baseline() {  # clean_baseline <n>: back to the baseline commit with no untracked or ignored files
  local d; d=$(clone_dir "$1")
  git -C "$d" switch -q -f ab-baseline && git -C "$d" clean -ffdxq
  [ "$(git -C "$d" rev-parse HEAD)" = "$(cat "$OUT/baseline.sha")" ] || die "clone$1: ab-baseline moved"
  [ -z "$(git -C "$d" status --porcelain --ignored)" ] || die "clone$1 isn't clean"
}

cmd_setup() {
  [ -e "$WS" ] && die "$WS exists; ./ab2.sh reset first"
  mkdir -p "$WS" "$OUT/logs"
  for n in "${CLONES[@]}"; do
    d=$(clone_dir "$n"); mkdir -p "$d"
    rsync -a --exclude target/ "$SRC"/ "$d"/
    git -C "$d" init -q -b ab-baseline
    GIT_AUTHOR_NAME=lab8 GIT_AUTHOR_EMAIL=lab8@localhost GIT_COMMITTER_NAME=lab8 GIT_COMMITTER_EMAIL=lab8@localhost \
    GIT_AUTHOR_DATE=2026-10-30T12:00:00Z GIT_COMMITTER_DATE=2026-10-30T12:00:00Z \
      sh -c "git -C '$d' add -A && git -C '$d' commit -q -m 'Ledger 1.4.0-SNAPSHOT'"
  done
  for n in "${CLONES[@]}"; do printf 'clone%s %s\n' "$n" "$(git -C "$(clone_dir "$n")" rev-parse HEAD)"; done | tee "$OUT/baselines.txt"
  [ "$(awk '{print $2}' "$OUT/baselines.txt" | sort -u | wc -l)" = 1 ] || die "baselines differ"
  awk 'NR==1{print $2}' "$OUT/baselines.txt" > "$OUT/baseline.sha"
  echo "all five baselines identical"
}

cmd_baseline() { clean_baseline 1; step "baseline: verify + probes"; check 1 baseline; clean_baseline 1; }

cmd_recipe() {
  for n in $(pick "$@"); do
    clean_baseline "$n"; d=$(clone_dir "$n")
    step "Side B clone$n: $RECIPE (OpenRewrite Maven plugin)"
    mvn_in "$n" "B-clone$n" "mvn -B $PLUGIN:run -Drewrite.configLocation=/lab/rewrite.yml \
      -Drewrite.activeRecipes=$RECIPE -Drewrite.recipeArtifactCoordinates=$RECIPE_JARS" || die "recipe failed (logs/B-clone$n.log)"
    git -C "$d" diff > "$OUT/B-clone$n.patch"
    git -C "$d" diff --stat | tail -1
    git -C "$d" switch -q -C side-b && git -C "$d" add -A ':!**/target/**' \
      && git -C "$d" -c user.name=lab8 -c user.email=lab8@localhost commit -qm "Side B: $RECIPE"
    git -C "$d" clean -ffdxq
  done
  (cd "$OUT" && sha256sum B-clone*.patch | tee B-sha256.txt)
  [ "$(awk '{print $1}' "$OUT/B-sha256.txt" | sort -u | wc -l)" = 1 ] && echo "all Side B patches identical" || echo "Side B patches DIFFER"
  step "Side B result: verify + probes (clone1)"
  git -C "$(clone_dir 1)" switch -q side-b; check 1 B-clone1; clean_baseline 1
}

cmd_agent() {
  : "${MODEL:?set MODEL, e.g. MODEL=claude-sonnet-5.5 ./ab2.sh agent}"
  EFFORT="${EFFORT:-medium}" TAG="${TAG:-}"
  [[ "$TAG" =~ ^[a-z0-9.-]*$ ]] || die "TAG may only use a-z 0-9 . -"
  MAX_RUN_CREDITS="${MAX_RUN_CREDITS:-200}" BUDGET="${BUDGET:-1450}"   # Copilot Pro: 1,500 credits/month
  [ -r "$TOKEN_FILE" ] && [ "$(stat -c %a "$TOKEN_FILE")" = 600 ] || die "token missing or not chmod 600: $TOKEN_FILE"
  need_agent
  for n in $(pick "$@"); do
    d=$(clone_dir "$n") A="A${TAG:+-$TAG}-clone$n" BR="side-a${TAG:+-$TAG}"
    [ -e "$OUT/$A.patch" ] && { echo "$A already done; skipping"; continue; }
    clean_baseline "$n"
    step "Side A $A: fresh Copilot session, model $MODEL"
    start=$(date +%s) eff=(--reasoning-effort "$EFFORT")
    for attempt in 1 2; do
      COPILOT_GITHUB_TOKEN="$(cat "$TOKEN_FILE")" docker run --rm --cpus 1.5 --label "$LABEL" \
        -e COPILOT_GITHUB_TOKEN -v "$d":/work/ledger -v "$OUT":/out -v moderne-lab-ab-m2:/home/lab/.m2 \
        -w /work/ledger moderne-lab-agent \
        copilot -p "$PROMPT" --model "$MODEL" "${eff[@]}" --allow-all --no-auto-update --disable-builtin-mcps \
          --secret-env-vars=COPILOT_GITHUB_TOKEN --output-format json --share "/out/$A.session.md" \
        > "$OUT/$A.jsonl" 2> "$OUT/logs/$A.stderr" || echo "copilot exited $? (see logs/$A.stderr)"
      if [ $attempt = 1 ] && grep -q 'Reasoning effort .* is not supported' "$OUT/logs/$A.stderr"; then
        echo "$A: $MODEL ran with its default effort (rejected $EFFORT)" | tee -a "$OUT/effort-overrides.txt"; eff=(); continue
      fi
      break
    done
    echo "$(( $(date +%s) - start ))s" > "$OUT/$A.seconds"
    if grep -q 'is not available' "$OUT/logs/$A.stderr" "$OUT/$A.jsonl" 2>/dev/null; then
      echo "$MODEL is not available on this plan; skipped" | tee -a "$OUT/unavailable-models.txt"
      rm -f "$OUT/$A".*; clean_baseline "$n"; continue
    fi
    read -r prem cred < <(python3 -I -c 'import json,sys
p=c="?"
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except ValueError: continue
    if e.get("type")=="session.usage_checkpoint":
        a=e.get("data",{}).get("accountingSnapshot",{}); c=round(a.get("totalNanoAiu",0)/1e9,2); p=a.get("totalPremiumRequestCost",p)
    if e.get("type")=="result": p=e.get("usage",{}).get("premiumRequests",p)
print(p,c)' "$OUT/$A.jsonl")
    printf 'premium_requests %s\nai_credits %s\n' "$prem" "$cred" > "$OUT/$A.cost"
    echo "$A $MODEL $prem $cred" >> "$OUT/spend.log"
    # One budget across Lab 8 and 8b: both spend the same monthly credits.
    total=$(cat "$OUT/spend.log" "$HERE/../ab/results/spend.log" 2>/dev/null | awk '$4 ~ /^[0-9.]+$/ {s+=$4} END{print s+0}')
    echo "this run: $prem premium requests, $cred credits; Lab 8 + 8b total: $total credits"
    stop=""
    if ! [[ "$cred" =~ ^[0-9.]+$ ]] || awk -v u="$cred" -v m="$MAX_RUN_CREDITS" -v t="$total" -v b="$BUDGET" 'BEGIN{exit !(u>m || t>b)}'; then
      echo "STOP: run cost '$cred' credits (limit $MAX_RUN_CREDITS) or total $total > budget $BUDGET"; stop=1
    fi
    base=$(cat "$OUT/baseline.sha")
    git -C "$d" add -A -N
    git -C "$d" diff "$base" -- . ':!**/target/**' > "$OUT/$A.patch"
    git -C "$d" log --oneline "$base..HEAD" > "$OUT/$A.commits"
    git -C "$d" diff --stat "$base" -- . ':!**/target/**' | tail -1
    git -C "$d" switch -q -C "$BR"
    git -C "$d" clean -ffdXq   # drop ignored build output (target/) the agent left; its new source files stay
    git -C "$d" add -A && git -C "$d" -c user.name=lab8 -c user.email=lab8@localhost commit -q --allow-empty -m "Side A $A ($MODEL)"
    check "$n" "$A"
    clean_baseline "$n"
    if [ -n "$stop" ]; then die "spend guard tripped after $A"; fi
  done
}

cmd_panel() {
  for n in $(pick "$@"); do
    for m in ${PANEL:-$PANEL_DEFAULT}; do TAG=${VARIANT:+$VARIANT-}$m MODEL=$m cmd_agent "$n"; done
  done
}

cmd_crosscheck() {  # dry-run the recipe on each agent result; a non-empty patch = it would still change something
  for br_tag in $(cd "$OUT" && ls A-*.patch 2>/dev/null | sed 's/\.patch$//'); do
    name=${br_tag#A-} n=${br_tag##*-clone}      # name: clone3 or grok-4.7-clone1
    tag=${name%-clone*}; [ "$tag" = "$name" ] && tag=""
    br="side-a${tag:+-$tag}" d=$(clone_dir "$n")
    git -C "$d" rev-parse -q --verify "$br" >/dev/null || continue
    [ -e "$OUT/X-$name.patch" ] && continue
    git -C "$d" switch -q -f "$br" && git -C "$d" clean -ffdxq
    step "cross-check $br_tag"
    # A failed dry run writes no X patch, so it can't be mistaken for "nothing to change".
    if ! mvn_in "$n" "X-$name" "mvn -B $PLUGIN:dryRun -Drewrite.configLocation=/lab/rewrite.yml \
      -Drewrite.activeRecipes=$RECIPE -Drewrite.recipeArtifactCoordinates=$RECIPE_JARS"; then
      echo "dry run FAILED for $br_tag (see logs/X-$name.log)" | tee -a "$OUT/crosscheck-failed.txt"
      clean_baseline "$n"; continue
    fi
    f="$d/target/rewrite/rewrite.patch"
    if [ -s "$f" ]; then cp "$f" "$OUT/X-$name.patch"; echo "recipe would still change $(grep -c '^diff --git' "$f") file(s)"
    else : > "$OUT/X-$name.patch"; echo "recipe has nothing to change"; fi
    clean_baseline "$n"
  done
}

cmd_status() { ls -1 "$OUT" 2>/dev/null | sed 's/^/  /' || echo "  nothing yet"; }

cmd_reset() {
  local dry=0; [ "${1:-}" = --dry-run ] && dry=1
  for p in "$WS" "$OUT"; do
    [ -e "$p" ] || continue
    if [ $dry = 1 ]; then echo "would remove $p ($(du -sh "$p" | cut -f1))"; else rm -rf "$p" && echo "removed $p"; fi
  done
  [ $dry = 1 ] && echo "(dry run: nothing removed)" || true
}

case "${1:-}" in
  setup|baseline|recipe|agent|panel|crosscheck|status|reset)
    c=$1; shift
    case $c in agent|recipe|panel) valid_n "$@" ;; esac
    [ "$c" = reset ] || mkdir -p "$OUT/logs"
    "cmd_$c" "$@" ;;
  *) sed -n 2,14p "$0"; exit 1 ;;
esac
