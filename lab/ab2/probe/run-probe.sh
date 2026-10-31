#!/bin/bash
# Run inside the agent image, in a container started with --network none:
#   run-probe.sh <ledger-app.jar> <out.jsonl>
# Starts the app, waits for it, runs Probe.java, stops the app. The canary is a random string written to a
# file the app can read; an exploit "works" if that string comes back in a response.
set -uo pipefail
JAR=$1 OUT=$2
CANARY="LEDGER-CANARY-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
mkdir -p /tmp/canary && printf '%s\n' "$CANARY" > /tmp/canary/secret.txt
startup_failed() {  # a fix that passes the build but stops the app from starting is a result, not a probe error
  cause=$(grep -m1 -E '^Caused by: ' <(tac /tmp/app.log) | cut -c1-300 | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"id":"startup","verdict":"BROKEN","where":"ledger-app","detail":"%s: %s"}\n' "$1" "$cause" > "$OUT"
  printf '%-12s %-11s %s\n' startup BROKEN "$1"; echo "  $cause"
  exit 0
}
[ -f "$JAR" ] || { printf '{"id":"startup","verdict":"BROKEN","where":"ledger-app","detail":"no jar: build failed"}\n' > "$OUT"; echo "no jar"; exit 0; }
java -jar "$JAR" --ledger.reports.dir=/tmp/ledger-reports > /tmp/app.log 2>&1 &
APP=$!
for _ in $(seq 1 90); do
  curl -sf -o /dev/null "http://localhost:8080/accounts/search?owner=nobody" && break
  kill -0 $APP 2>/dev/null || startup_failed "app exited during startup"
  sleep 1
done
curl -sf -o /dev/null "http://localhost:8080/accounts/search?owner=nobody" || { kill $APP; startup_failed "app not up after 90s"; }
java "$(dirname "$0")/Probe.java" /tmp/canary/secret.txt "$CANARY" "$OUT"
rc=$?
kill $APP; wait $APP 2>/dev/null
exit $rc
