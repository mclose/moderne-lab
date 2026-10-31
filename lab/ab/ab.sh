#!/bin/bash
# Lab 8: one security fix, five agent runs vs. one recipe (10-lab8-agent-vs-recipe.md).
#   ./ab.sh setup              5 clones at the pinned commit, plant log4j-core 2.14.1, commit ab-baseline, check trees match
#   ./ab.sh baseline           ./mvnw -q verify on clone1's baseline (the five trees are identical)
#   ./ab.sh agent [N...]       Side A: one fresh Copilot CLI session per clone (default 1-5); needs MODEL and a token file
#   ./ab.sh recipe [N...]      Side B: lab.FixLog4Shell on each clone's baseline (default 1-5), hash the patches
#   ./ab.sh apply              apply Side B on clone1 (branch side-b), rebuild, rerun (must be empty), verify
#   ./ab.sh inventory          DependencyInsight on baselines, Side A results and the patched Side B clone
#   ./ab.sh regress            plant 2.14.1 in vets-service on side-b, rerun the recipe, show what it finds
#   ./ab.sh crosscheck [N...]  run the recipe on each Side A result
#   ./ab.sh panel [N...]       the same prompt on other models (PANEL="m1 m2 ..."), in rounds, tagged per model
#   ./ab.sh panel_check        cross-check + inventory for each panel model
#   ./ab.sh status             what's done so far
#   ./ab.sh reset [--dry-run]  delete ws/ and results/ (clones, patches, logs)
# Everything runs in Docker at --cpus 1.5, one container at a time. Uninstall: ../uninstall.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HERE/ws" OUT="$HERE/results"
REPO=https://github.com/spring-petclinic/spring-petclinic-microservices
COMMIT=e8b747ab522721076cacb5cf688eb8a54ba8c5c9
RECIPE=lab.FixLog4Shell
INSIGHT=org.openrewrite.java.dependencies.DependencyInsight
DEPS_VERSION=1.60.2   # rewrite-java-dependencies: UpgradeDependencyVersion + DependencyInsight (not in the Lab 2 set)
PROMPT='Our security scanner flagged CVE-2021-44228 (Log4Shell) in this repo. Fix it so the build still passes.'
TOKEN_FILE="${COPILOT_TOKEN_FILE:-$HOME/.config/moderne-lab/copilot.token}"
LABEL=course=moderne-lab
CLONES=(1 2 3 4 5)

step() { echo; echo "######## $* ($(date +%T))"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
clone_dir() { echo "$WS/clone$1"; }
pick() { [ $# -gt 0 ] && echo "$@" || echo "${CLONES[@]}"; }
valid_n() { for n in "$@"; do [[ "$n" =~ ^[1-5]$ ]] || die "clone number must be 1-5, got '$n'"; done; }

# Images: built on first use, labelled so uninstall finds them.
need_cli()   { docker image inspect moderne-lab-cli >/dev/null 2>&1 \
                 || docker build --label "$LABEL" -t moderne-lab-cli "$HERE/../cli"; }
need_agent() { docker image inspect moderne-lab-agent >/dev/null 2>&1 \
                 || docker build --label "$LABEL" -t moderne-lab-agent -f "$HERE/Dockerfile.agent" "$HERE"; }

# run_mod <clone dir name> <log> <commands>: Moderne CLI container, Lab 2 volume (recipes, caches).
run_mod() {
  need_cli
  docker run --rm --cpus 1.5 --label "$LABEL" -u 1001:1001 \
    -v "$WS":/ws -v "$HERE":/lab:ro -v moderne-lab-home:/home/lab \
    -w "/ws/$1" moderne-lab-cli bash -c "set -euxo pipefail; $3" > "$OUT/logs/$2.log" 2>&1 \
    || { echo "FAILED: see $OUT/logs/$2.log"; tail -25 "$OUT/logs/$2.log"; return 1; }
}
# run_dev <clone dir name> <log> <commands>: the agent image without the agent, for mvnw verify.
run_dev() {
  need_agent
  docker run --rm --cpus 1.5 --label "$LABEL" -v "$WS":/ws -v moderne-lab-ab-m2:/home/lab/.m2 \
    -w "/ws/$1" moderne-lab-agent bash -c "$3" > "$OUT/logs/$2.log" 2>&1
}
verify() {  # verify <clone dir name> <log>: prints PASS/FAIL, never aborts the script
  if run_dev "$1" "$2" 'java -version 2>&1 | head -1; ./mvnw -q verify'; then echo PASS; else echo FAIL; fi
}
newest_run() { ls -td "$(clone_dir "$1")"/.moderne/run/*/ 2>/dev/null | head -1; }

plant() {  # insert log4j-core 2.14.1 right after jolokia-core in a module pom; same bytes every time
  python3 -I - "$1" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
anchor = "<artifactId>jolokia-core</artifactId>\n        </dependency>\n"
if s.count(anchor) != 1: sys.exit(f"anchor not found exactly once in {p}")
dep = ("        <dependency>\n"
       "            <groupId>org.apache.logging.log4j</groupId>\n"
       "            <artifactId>log4j-core</artifactId>\n"
       "            <version>2.14.1</version>\n"
       "        </dependency>\n")
p.write_text(s.replace(anchor, anchor + dep))
PY
}

cmd_setup() {
  [ -e "$WS" ] && die "$WS exists; ./ab.sh reset first"
  mkdir -p "$WS" "$OUT/logs"
  step "clone $REPO once, then 5 local copies at $COMMIT"
  git clone -q "$REPO" "$WS/.mirror"
  for n in "${CLONES[@]}"; do
    d=$(clone_dir "$n")
    git clone -q "$WS/.mirror" "$d"
    git -C "$d" remote set-url origin "$REPO"   # mod checks the origin to decide the repo is public
    git -C "$d" switch -q -c ab-baseline "$COMMIT"
    plant "$d/spring-petclinic-customers-service/pom.xml"
    # Fixed author and dates, so the five baseline commits are byte-identical, not just the trees.
    GIT_AUTHOR_NAME=lab8 GIT_AUTHOR_EMAIL=lab8@localhost GIT_COMMITTER_NAME=lab8 GIT_COMMITTER_EMAIL=lab8@localhost \
    GIT_AUTHOR_DATE=2026-10-30T12:00:00Z GIT_COMMITTER_DATE=2026-10-30T12:00:00Z \
      git -C "$d" commit -q -am "Lab 8: plant log4j-core 2.14.1 (CVE-2021-44228) in customers-service"
  done
  rm -rf "$WS/.mirror"
  step "baselines"
  for n in "${CLONES[@]}"; do
    printf 'clone%s  HEAD %s  tree %s\n' "$n" "$(git -C "$(clone_dir "$n")" rev-parse HEAD)" \
      "$(git -C "$(clone_dir "$n")" rev-parse 'HEAD^{tree}')"
  done | tee "$OUT/baselines.txt"
  [ "$(awk '{print $5}' "$OUT/baselines.txt" | sort -u | wc -l)" = 1 ] && echo "all five trees identical" \
    || die "baseline trees differ"
  git -C "$(clone_dir 1)" show --stat --format='%h %s' HEAD | tee "$OUT/plant.txt"
}

cmd_baseline() {
  step "./mvnw -q verify on the baseline (clone1)"
  r=$(verify clone1 baseline-verify); echo "$r" | tee "$OUT/baseline-verify.txt"
  [ "$r" = PASS ] || { tail -40 "$OUT/logs/baseline-verify.log"; die "baseline doesn't build; stopping as the brief says"; }
}

cmd_agent() {
  : "${MODEL:?set MODEL to the Copilot model id, e.g. MODEL=claude-sonnet-5.5 ./ab.sh agent (copilot help config lists them)}"
  EFFORT="${EFFORT:-medium}"   # Copilot's default for the default model; pinned so all runs of a model match
  # TAG names the experiment: empty = the brief's main run (A-cloneN, branch side-a); anything else is an
  # extra model (A-<tag>-cloneN, branch side-a-<tag>), so runs never overwrite each other.
  TAG="${TAG:-}"; [[ "$TAG" =~ ^[a-z0-9.-]*$ ]] || die "TAG may only use a-z 0-9 . -"
  MAX_RUN_CREDITS="${MAX_RUN_CREDITS:-200}" BUDGET="${BUDGET:-1450}"   # Copilot Pro: 1,500 credits/month; no paid overage
  [ -r "$TOKEN_FILE" ] || die "no token at $TOKEN_FILE (fine-grained PAT with only 'Copilot Requests')"
  [ "$(stat -c %a "$TOKEN_FILE")" = 600 ] || die "$TOKEN_FILE must be chmod 600"
  need_agent
  base=$(git -C "$(clone_dir 1)" rev-parse ab-baseline)
  for n in $(pick "$@"); do
    d=$(clone_dir "$n"); [ -d "$d" ] || die "clone$n missing; ./ab.sh setup"
    A="A${TAG:+-$TAG}-clone$n" BR="side-a${TAG:+-$TAG}"
    [ -e "$OUT/$A.patch" ] && { echo "$A already done (results/$A.patch); skipping"; continue; }
    git -C "$d" switch -q ab-baseline
    [ "$(git -C "$d" rev-parse HEAD)" = "$base" ] && [ -z "$(git -C "$d" status --porcelain)" ] \
      || die "clone$n isn't clean at ab-baseline ($base)"
    # Remove ignored files too: Side B's .moderne/ holds the recipe's fix.patch, and build output would
    # tell the agent the build was already run. The agent starts from exactly the committed baseline.
    git -C "$d" clean -ffdxq
    [ -z "$(git -C "$d" status --porcelain --ignored)" ] || die "clone$n still has untracked or ignored files"
    step "Side A $A: fresh Copilot session, model $MODEL, effort $EFFORT"
    # Fresh container = fresh ~/.copilot (no memory, sessions or config). Token comes from the env and is
    # stripped from the agent's own shell. The container is the sandbox, so the agent gets --allow-all.
    start=$(date +%s) eff=(--reasoning-effort "$EFFORT")
    for attempt in 1 2; do
      COPILOT_GITHUB_TOKEN="$(cat "$TOKEN_FILE")" docker run --rm --cpus 1.5 --label "$LABEL" \
        -e COPILOT_GITHUB_TOKEN -v "$d":/work/spring-petclinic-microservices -v "$OUT":/out \
        -v moderne-lab-ab-m2:/home/lab/.m2 -w /work/spring-petclinic-microservices moderne-lab-agent \
        copilot -p "$PROMPT" --model "$MODEL" "${eff[@]}" --allow-all --no-auto-update --disable-builtin-mcps \
          --secret-env-vars=COPILOT_GITHUB_TOKEN --output-format json --share "/out/$A.session.md" \
        > "$OUT/$A.jsonl" 2> "$OUT/logs/$A.stderr" || echo "copilot exited $? (see logs/$A.stderr)"
      # Some models (kimi-k3) reject an explicit effort level before doing anything: rerun once on their default.
      if [ $attempt = 1 ] && grep -q 'Reasoning effort .* is not supported' "$OUT/logs/$A.stderr"; then
        echo "$MODEL rejects --reasoning-effort $EFFORT; rerunning with the model's default effort"
        echo "$A: $MODEL ran with its default effort (rejected $EFFORT)" >> "$OUT/effort-overrides.txt"
        eff=(); continue
      fi
      break
    done
    echo "$(( $(date +%s) - start ))s" > "$OUT/$A.seconds"
    if grep -q 'is not available' "$OUT/logs/$A.stderr" "$OUT/$A.jsonl" 2>/dev/null; then
      echo "$MODEL is not available on this plan; skipped" | tee -a "$OUT/unavailable-models.txt"
      rm -f "$OUT/$A".*; git -C "$d" checkout -q -- . && git -C "$d" clean -ffdxq; continue
    fi
    # Spend guard. Copilot reports two meters: premium requests (1 per prompt) and AI credits (per token,
    # summed over every model call; nanoAiu / 1e9). Pro+ budgets are in credits, so the guard watches those.
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
    total=$(awk '{s+=$4} END{print s+0}' "$OUT/spend.log")
    echo "this run: $prem premium requests, $cred AI credits; lab total so far: $total credits"
    if ! [[ "$cred" =~ ^[0-9.]+$ ]] || awk -v u="$cred" -v m="$MAX_RUN_CREDITS" -v t="$total" -v b="$BUDGET" \
         'BEGIN{exit !(u>m || t>b)}'; then
      echo "STOP: run cost '$cred' credits (limit $MAX_RUN_CREDITS) or total $total > budget $BUDGET"
      stop_after=1
    fi
    # Save the agent's work exactly as left, against the fixed baseline commit (the agent may have committed,
    # even onto ab-baseline). -N records new files without staging their content.
    git -C "$d" add -A -N
    git -C "$d" diff "$base" > "$OUT/$A.patch"
    git -C "$d" log --oneline "$base..HEAD" > "$OUT/$A.commits"
    git -C "$d" diff --stat "$base" | tail -1
    r=$(verify "clone$n" "$A-verify"); echo "$r" | tee "$OUT/$A.verify"
    # Keep the result on its own branch, then put ab-baseline back exactly where it was.
    git -C "$d" switch -q -C "$BR"
    git -C "$d" add -A && git -C "$d" -c user.name=lab8 -c user.email=lab8@localhost commit -q --allow-empty -m "Side A result $A ($MODEL)"
    git -C "$d" switch -q -f -C ab-baseline "$base" && git -C "$d" clean -ffdxq
    if [ -n "${stop_after:-}" ]; then die "spend guard tripped after $A"; fi
  done
}

install_recipe() {  # the YAML lives in lab/ab, outside the clones; the CLI copies it into its recipe catalog
  echo "mod config recipes jar install org.openrewrite.recipe:rewrite-java-dependencies:$DEPS_VERSION; mod config recipes yaml install /lab/rewrite.yml"
}

cmd_recipe() {
  for n in $(pick "$@"); do
    d=$(clone_dir "$n")
    git -C "$d" switch -q ab-baseline && [ -z "$(git -C "$d" status --porcelain)" ] || die "clone$n not clean at ab-baseline"
    step "Side B clone$n: mod build + $RECIPE"
    run_mod "clone$n" "B-clone$n" "mod --version; $(install_recipe); mod build .; mod run . --recipe $RECIPE"
    f="$(newest_run "$n")fix.patch"; [ -s "$f" ] || die "clone$n: no fix.patch"
    cp "$f" "$OUT/B-clone$n.patch"
  done
  step "Side B hashes"
  (cd "$OUT" && sha256sum B-clone*.patch | tee B-sha256.txt)
  [ "$(awk '{print $1}' "$OUT/B-sha256.txt" | sort -u | wc -l)" = 1 ] && echo "all Side B patches identical" || echo "Side B patches DIFFER"
}

cmd_apply() {
  d=$(clone_dir 1)
  git -C "$d" switch -q ab-baseline
  step "apply Side B on clone1 (branch side-b), rebuild the LST, rerun"
  run_mod clone1 B-apply "git switch -c side-b; mod git apply . --last-recipe-run; git diff --stat | tail -1;
    git -c user.name=lab8 -c user.email=lab8@localhost commit -qam 'Side B: $RECIPE'; mod build .; mod run . --recipe $RECIPE"
  f="$(newest_run 1)fix.patch"
  if [ -s "$f" ]; then echo "rerun NOT empty: $f" | tee "$OUT/B-rerun.txt"; else echo "rerun produced no fix.patch (empty)" | tee "$OUT/B-rerun.txt"; fi
  r=$(verify clone1 B-verify); echo "$r" | tee "$OUT/B-clone1.verify"
}

# insight <clone n> <branch> <tag>: DependencyInsight data table -> results/insight-<tag>.csv
insight() {
  local n=$1 br=$2 tag=$3
  [ -e "$OUT/insight-$tag.csv" ] && { echo "insight-$tag.csv exists; skipping"; return 0; }
  git -C "$(clone_dir "$n")" switch -q "$br"
  run_mod "clone$n" "insight-$tag" "mod build .; mod run . --recipe $INSIGHT \
    -P groupIdPattern=org.apache.logging.log4j -P 'artifactIdPattern=*'; \
    mod study . --last-recipe-run --data-table org.openrewrite.maven.table.DependenciesInUse" \
    || { echo "$tag: inventory failed (logs/insight-$tag.log)" | tee -a "$OUT/insight-missing.txt"; return 0; }
  f=$(ls -t "$(clone_dir "$n")"/.moderne/run/*/datatables/org.openrewrite.maven.table.DependenciesInUse.csv 2>/dev/null | head -1) || true
  [ -n "$f" ] && cp "$f" "$OUT/insight-$tag.csv" || echo "$tag: no DependenciesInUse table" | tee -a "$OUT/insight-missing.txt"
}

cmd_inventory() {
  for n in "${CLONES[@]}"; do step "inventory baseline clone$n"; insight "$n" ab-baseline "base-clone$n"; done
  for n in "${CLONES[@]}"; do
    BR="side-a${TAG:+-$TAG}" A="A${TAG:+-$TAG}-clone$n"
    git -C "$(clone_dir "$n")" rev-parse -q --verify "$BR" >/dev/null || { echo "clone$n has no $BR; skipped"; continue; }
    step "inventory Side A $A"; insight "$n" "$BR" "$A"
  done
  step "inventory Side B clone1"; insight 1 side-b B-clone1
  git -C "$(clone_dir 1)" switch -q ab-baseline
}

cmd_regress() {
  d=$(clone_dir 1)
  git -C "$d" switch -q side-b
  git -C "$d" switch -q -c regress
  step "regression: plant 2.14.1 in vets-service (nobody tells the recipe where)"
  python3 -I - "$d/spring-petclinic-vets-service/pom.xml" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
m = list(re.finditer(r"^[ \t]*<dependencies>[ \t]*\n", s, re.M))   # vets-service indents with tabs
if len(m) != 1: sys.exit(f"expected one <dependencies> in {p}, found {len(m)}")
dep = ("        <dependency>\n            <groupId>org.apache.logging.log4j</groupId>\n"
       "            <artifactId>log4j-core</artifactId>\n            <version>2.14.1</version>\n        </dependency>\n")
p.write_text(s[:m[0].end()] + dep + s[m[0].end():])
PY
  git -C "$d" -c user.name=lab8 -c user.email=lab8@localhost commit -qam "regression: log4j-core 2.14.1 in vets-service"
  run_mod clone1 regress "mod build .; mod run . --recipe $RECIPE"
  f="$(newest_run 1)fix.patch"; [ -s "$f" ] && cp "$f" "$OUT/regress.patch" && grep '^diff --git' "$OUT/regress.patch" \
    || echo "regression NOT caught: no fix.patch"
  git -C "$d" switch -q ab-baseline
}

cmd_crosscheck() {
  for n in $(pick "$@"); do
    d=$(clone_dir "$n")
    BR="side-a${TAG:+-$TAG}" X="X${TAG:+-$TAG}-clone$n"
    git -C "$d" rev-parse -q --verify "$BR" >/dev/null || { echo "clone$n has no $BR; skipped"; continue; }
    [ -e "$OUT/$X.patch" ] && { echo "$X.patch exists; skipping"; continue; }
    git -C "$d" switch -q "$BR"
    step "cross-check: $RECIPE on Side A $BR clone$n"
    # Install the recipe every time: the CLI's catalog doesn't keep it between runs. A failed run must not
    # be read as "nothing to change", so it leaves no X patch and the next crosscheck retries it.
    if ! run_mod "clone$n" "$X" "$(install_recipe); mod build .; mod run . --recipe $RECIPE"; then
      echo "$X: cross-check FAILED (logs/$X.log)" | tee -a "$OUT/crosscheck-failed.txt"
      git -C "$d" switch -q ab-baseline && git -C "$d" clean -ffdxq; continue
    fi
    f="$(newest_run "$n")fix.patch"
    if [ -s "$f" ]; then cp "$f" "$OUT/$X.patch"; echo "recipe still changes: $(grep -c '^diff --git' "$f") file(s)"
    else : > "$OUT/$X.patch"; echo "recipe has nothing to change"; fi
    git -C "$d" switch -q ab-baseline && git -C "$d" clean -ffdxq
  done
}

# Extra models, same prompt. Rounds (clone1 for every model, then clone2, ...) so that if the credit budget
# runs out, every model still has runs to compare. Each model's results are tagged with its name.
# The panel run on 2026-10-30 (Copilot Pro). gpt-6.1-sol and gemini-4-argon were not on that plan.
PANEL_DEFAULT="gpt-6-luna gpt-5.3-codex gemini-3.8-flash mai-code-1.1-flash grok-4.7 kimi-k3 claude-haiku-5.5"
cmd_panel() {
  for n in $(pick "$@"); do
    for m in ${PANEL:-$PANEL_DEFAULT}; do
      TAG=$m MODEL=$m cmd_agent "$n"
    done
  done
}
cmd_panel_check() {  # cross-check + inventory for each panel model (Moderne CLI only, no credits)
  for m in ${PANEL:-$PANEL_DEFAULT}; do
    TAG=$m cmd_crosscheck
    for n in "${CLONES[@]}"; do
      BR="side-a-$m"; git -C "$(clone_dir "$n")" rev-parse -q --verify "$BR" >/dev/null || continue
      step "inventory $m clone$n"; insight "$n" "$BR" "A-$m-clone$n"
    done
  done
  git -C "$(clone_dir 1)" switch -q ab-baseline
}

cmd_status() {
  ls -1 "$OUT" 2>/dev/null | sed 's/^/  /' || echo "  nothing yet"
}

cmd_reset() {
  local dry=0; [ "${1:-}" = --dry-run ] && dry=1
  for p in "$WS" "$OUT"; do
    [ -e "$p" ] || continue
    if [ $dry = 1 ]; then echo "would remove $p ($(du -sh "$p" | cut -f1))"; else rm -rf "$p" && echo "removed $p"; fi
  done
  [ $dry = 1 ] && echo "(dry run: nothing removed)" || true
}

case "${1:-}" in
  setup|baseline|agent|recipe|apply|inventory|regress|crosscheck|panel|panel_check|status|reset)
    c=$1; shift
    case $c in agent|recipe|crosscheck|panel) valid_n "$@" ;; esac
    [ "$c" = reset ] || mkdir -p "$OUT/logs"
    "cmd_$c" "$@" ;;
  *) sed -n 2,15p "$0"; exit 1 ;;
esac
