# Lab 8: one security fix, agents vs. a recipe

**Goal:** ask Copilot coding agents to fix the same security problem again and again from the same starting point,
and compare what they write with what one OpenRewrite recipe writes. Lab 8 uses one planted CVE. Lab 8b uses a
scanner ticket on a small app with real, exploitable holes, which is closer to how this work happens.

**Needs:** Docker, the `moderne-lab-cli` image from Lab 2, and a GitHub Copilot plan (a personal Pro plan is enough).
The agent runs in a container built by the lab, so nothing is installed on your machine and you never open VS Code.
Lab 8 used about 310 AI credits, and 8b about 610.

**Drift board:** [Agent drift board](https://claude.ai/artifact/UFgomKz3TdHRAK6UnjaYwN) (private until shared). It is
built from `lab/board/*.csv`, which `lab/board/make_board_data.py` regenerates from the result files.

Results below are from **2026-10-30**: Copilot CLI 1.0.105 in headless mode, Moderne CLI 4.12.0, OpenRewrite Maven
plugin 6.46.1, rewrite-java-dependencies 1.60.2, rewrite-java-security 3.38.1.

## How an agent run works

Every agent run is one fresh Copilot CLI session in a throwaway container:

```bash
copilot -p "$PROMPT" --model "$MODEL" --reasoning-effort medium --allow-all --no-auto-update \
  --disable-builtin-mcps --secret-env-vars=COPILOT_GITHUB_TOKEN --output-format json --share session.md
```

- **Token:** a fine-grained GitHub token with only the *Copilot Requests* permission, read from
  `~/.config/moderne-lab/copilot.token` (mode 600). It reaches the container through `COPILOT_GITHUB_TOKEN`, and
  `--secret-env-vars` keeps the agent from reading it back. Revoke the token when you're done.
- **Isolation:** before each session the clone is reset to the baseline commit, and every untracked and ignored file
  is deleted (`git clean -ffdx`), so no session sees an earlier one's work or the recipe's patch.
- **Saved per run:** the patch against the baseline (`A-*.patch`), the full session transcript (`*.session.md`), the
  JSON event log, credits and seconds, and the build result. Nothing the agent wrote is edited.
- **Spend guard:** the harness reads each session's own usage report. It stops if one run goes over 200 credits
  or the lab total goes over 1,450.
- `kimi-k3` rejects `--reasoning-effort medium`, so the harness retries it once without the flag and notes that in
  `effort-overrides.txt`.

## Lab 8: Log4Shell in spring-petclinic-microservices

**Target:** `spring-petclinic-microservices` at `e8b747ab`, with `log4j-core 2.14.1` planted in customers-service.
Five clones, all at the same baseline commit `f11608c` (fixed author and dates, so the hashes match).

**Agent prompt, word for word:** "Our security scanner flagged CVE-2021-44228 (Log4Shell) in this repo. Fix it so the
build still passes."

**Recipe:** `lab.FixLog4Shell` in `lab/ab/rewrite.yml`, one `UpgradeDependencyVersion` to 2.26.1 (the newest 2.x).

```bash
cd ~/projects/general_chat/moderne.ai/lab/ab
./ab.sh reset --dry-run       # what a reset would delete
./ab.sh setup && ./ab.sh baseline
./ab.sh recipe && ./ab.sh apply && ./ab.sh regress
MODEL=claude-sonnet-5.5 ./ab.sh agent
./ab.sh inventory && ./ab.sh crosscheck
./ab.sh panel && ./ab.sh panel_check     # the seven other models, five runs each
```

### The recipe: one patch, five times

All five Side B patches have sha256 `14f7b7eb…5c9523`: one line, `2.14.1` → `2.26.1`. Rebuilding the LST on the
patched clone and running the recipe again gave **no patch**. `mvnw verify` passed. Then I planted 2.14.1 again in
vets-service without telling the recipe where. The rerun found it and made the same one-line bump.

### The agents: six different fixes

Forty sessions, eight models, five each. **Every one passed the build, and every one closed the CVE.** They closed it
in six different ways:

| Fix | Agent runs | log4j-core in the build |
|---|---|---|
| Remove the dependency | 21 | none |
| Drop the `<version>`, so Spring Boot's BOM picks it | 9 | 2.25.3 |
| Bump to 2.17.2 | 7 | 2.17.2 |
| Bump to 2.26.1 (the same bytes as the recipe, apart from the hunk header) | 1 | 2.26.1 |
| `${log4j2.version}` on core, and add `log4j-api` | 1 | 2.25.3 |
| Drop the `<version>` and add a warning comment | 1 | 2.25.3 |

| Model | Five runs gave | Credits (5 runs) |
|---|---|---|
| claude-sonnet-5.5 (plan default) | remove ×5, byte-identical | 31.8 |
| claude-haiku-5.5 | drop version ×5, byte-identical | 3.0 |
| mai-code-1.1-flash | bump to 2.17.2 ×5, byte-identical | 3.1 |
| gpt-6-luna | remove ×4, drop version ×1 | 4.5 |
| kimi-k3 | remove ×4, drop version ×1 | 53.6 |
| gemini-3.8-flash | bump to 2.26.1 ×1, remove ×4 | 65.3 |
| gpt-5.3-codex | 2.17.2 ×2, remove ×2, drop version ×1 | 38.8 |
| grok-4.7 | four different fixes in five runs | 106.5 |

**What this shows:**

- **One model on its own can look deterministic.** Sonnet gave the same patch, byte for byte, five times out of five.
  The brief said to report that rather than keep rerunning until something changed. So did Haiku and MAI.
  If you only ever try one model, you might conclude agents don't drift.
- **Across models they do, and inside five of the eight models too.** The prompt didn't change and the repo didn't
  change. What you get depends on which model your plan routes the request to that day.
- **Every fix is "correct" by the prompt's test,** and the build passes. They are not the same change to review:
  removing a dependency someone added on purpose, pinning an old patch release (2.17.2 is past Log4Shell but behind
  later CVE fixes), handing the version to the BOM, or pinning the newest. That's a policy choice, and the agent
  made it differently each time.
- **Cost varies by 35×** for the same outcome (grok-4.7 vs. claude-haiku-5.5), and the cheap models were the most
  consistent.

**Cross-check (the recipe run on top of each agent result):** the recipe still changed **8 of 40** results. On all
seven 2.17.2 pins it bumped `2.17.2` → `2.26.1`. On grok's `${log4j2.version}` run it added a `log4j2.version` 2.26.1
property, which overrides the version Spring Boot manages. It changed nothing where the agent removed the dependency or
left the version to the BOM: the recipe upgrades versions a pom declares, and those runs declare none. Both of those
fixes stay safe only as long as no other module, and no later commit, brings in an old log4j-core.

**Inventory:** on the baseline, `log4j-api` is already 2.25.3 (from Spring Boot's BOM) next to `log4j-core 2.14.1`.
That mismatch is why "drop the version" works: the BOM pulls core up to 2.25.3 to match.

## Lab 8b: a scanner ticket on an app with real holes

Lab 8 has one right answer and a build that can't tell the fixes apart. Real work is messier: a scanner report,
several findings, code written by different teams, and holes the scanner doesn't list. Lab 8b recreates that.

**Target:** `lab/ab2/ledger/`, a small back-office ledger written for this lab: Spring Boot 4, Java 17, five Maven
modules, about 900 lines, written in three team styles (legacy, modern records-and-`var`, and copy-paste). No model
can have seen it before. It has **seven exploitable holes**. The scanner ticket names five findings, and three of the
holes aren't in it:

| Hole | Where | In the ticket? |
|---|---|---|
| Text4Shell (commons-text 1.9, used for real) | `NoticeRenderer` | yes |
| commons-configuration2 2.7 (CVE-2022-33980, brings commons-text 1.8) | parent pom | yes |
| XXE via `DocumentBuilderFactory` | `StatementImporter` | yes |
| XXE via `XMLInputFactory` (StAX) | `ReportMetadataReader` | **no** |
| XXE via `SAXParserFactory` | `AccountListImporter` | **no** |
| Zip Slip | `ReportArchiveService` | yes |
| SQL injection in account search | `AccountRepository.findByOwner` | yes |
| SQL injection copy-pasted into the overdraft report | `AccountRepository.findOverdrawn` | **no** |

**Agent prompt:** the scanner report in `lab/ab2/ab2.sh` (`PROMPT`), five findings with file and line, and "Fix them so
the build still passes."

**Recipe:** `lab.LedgerScannerFindings` in `lab/ab2/rewrite.yml`: upgrade commons-text to 1.15.0 (direct and
transitive) and commons-configuration2 to 2.15.1, then `XmlParserXXEVulnerability`, `ZipSlip` and
`FixSqlInjectionConcat` from rewrite-java-security.

**How a fix is judged:** `./mvnw clean verify`, then an exploit probe. The built jar starts in a container with
`--network none`. `lab/ab2/probe/Probe.java`, which lives outside the repo so no agent can fix to the test, sends each
hole a normal request and a real attack: an XXE that reads a random canary file, `${url:UTF-8:file://…}` for
Text4Shell, a `../` zip entry, and `' OR '1'='1`-style SQL. Each hole gets **SAFE** (the feature works and the attack
fails), **VULNERABLE**, or **BROKEN** (the feature stopped working). If the app doesn't start, that is recorded and
nothing else can be probed. Before trusting the probe, I checked that it gives both answers: the untouched app is
VULNERABLE on all seven, and a partly fixed build was SAFE exactly where its code was fixed.

```bash
cd ~/projects/general_chat/moderne.ai/lab/ab2
./ab2.sh reset --dry-run
./ab2.sh setup && ./ab2.sh baseline
./ab2.sh recipe
MODEL=claude-sonnet-5.5 ./ab2.sh agent
./ab2.sh panel        # gpt-5.3-codex, grok-4.7, gemini-3.8-flash, five runs each
PANEL="gpt-6-luna mai-code-1.1-flash kimi-k3 claude-haiku-5.5" ./ab2.sh panel
./ab2.sh crosscheck
# the same ticket plus "start the app" (runs tagged start-<model>)
VARIANT=start PANEL="claude-sonnet-5.5 gpt-5.3-codex kimi-k3 gpt-6-luna mai-code-1.1-flash claude-haiku-5.5" ./ab2.sh panel
# the same, with the three unnamed holes added to the ticket, or with "look past the ticket" (start line kept in both)
# BUDGET counts every credit the harness has logged, across months; raise it by each month's allowance
BUDGET=2850 VARIANT=named PANEL="claude-sonnet-5.5 gpt-5.3-codex kimi-k3 gpt-6-luna mai-code-1.1-flash claude-haiku-5.5" ./ab2.sh panel
BUDGET=2850 VARIANT=lookpast PANEL="claude-sonnet-5.5 gpt-5.3-codex kimi-k3 gpt-6-luna mai-code-1.1-flash claude-haiku-5.5" ./ab2.sh panel
```

### Results

**Forty agent runs (eight models, five runs each) gave forty different patches.** All forty passed `mvnw verify`.
The first 20 ran on 2026-10-30. The second four models ran on 2026-10-31, with the same prompt and harness.

| Model | Started | All 7 safe | Typical result when it started | Credits (5 runs) |
|---|---|---|---|---|
| claude-sonnet-5.5 | 3 of 5 | 2 | 2 runs closed everything; 1 left both unnamed XXEs | 57.4 |
| gpt-5.3-codex | 5 of 5 | 0 | 5 of 7: both unnamed XXEs open | 82.6 |
| gemini-3.8-flash | 5 of 5 | 0 | 5 of 7: both unnamed XXEs open | 154.5 |
| grok-4.7 | 1 of 5 | 0 | 5 of 7: both unnamed XXEs open | 319.8 |
| kimi-k3 | 5 of 5 | 0 | 5 of 7: both unnamed XXEs open | 97.5 |
| gpt-6-luna | 5 of 5 | 0 | 5 of 7: both unnamed XXEs open | 10.9 |
| mai-code-1.1-flash | 4 of 5 | 0 | 5 of 7: both unnamed XXEs open | 9.5 |
| claude-haiku-5.5 | 5 of 5 | 0 | 5 of 7: both unnamed XXEs open | 7.4 |
| recipe (5 identical patches) | 0 of 5 | 0 | app won't start | 0 |

- **The upgrade trap.** commons-configuration2 2.15.1, the newest release, added a URL-scheme allowlist that
  rejects Spring Boot's `nested:` jar URLs. `ConfigurationDeniedException: URL scheme "nested" is not enabled`, and
  the jar won't start. Unit tests pass, so `mvnw verify` stays green. **Every run that picked 2.15.1 broke startup:
  the recipe (5 of 5), grok (4 of 5), Sonnet (2 of 5) and MAI (1 of 5).** Every run on 2.12.0 or older started,
  and so did the one run (MAI clone5) that deleted commons-configuration2 and commons-text and rewrote the code that
  used them. No agent saw the error. Of the 40 transcripts, only one (gemini clone3) shows the agent starting the
  jar, and it was on 2.11.0. The runs that avoided the trap did so
  for other reasons: grok checked which commons-lang3 each release needs, and the rest just picked a version they
  knew was fixed.
- **The ticket sets the scope.** 33 agent runs started. Apart from Sonnet's two complete runs, all 31 left the
  StAX and SAX XXEs open, the two the ticket doesn't name. Every started run fixed **both** SQL injections, including the
  copy-pasted one the ticket doesn't name, because it sits in the same file as the named one.
- **The recipe fixes what its recipes know about.** With commons-configuration2 held at 2.7 so the app starts (the
  harness's validation build), the recipe's code fixes closed the DOM and StAX XXEs, Text4Shell and Zip Slip. They
  missed the SAX XXE and both SQL injections: `FixSqlInjectionConcat` doesn't recognise the `JdbcTemplate`
  string-concatenation pattern. It also added redundant `dependencyManagement` blocks to three poms. Its five patches
  were byte-identical, sha256 `8d02cd5b…7f5ca7`.
- **Consistency on Log4Shell didn't carry over.** Haiku and MAI gave one byte-identical patch five times in Lab 8.
  Here each wrote five different patches. The probe results still converged: every Haiku, gpt-6-luna and kimi-k3
  run scored exactly the same 5 of 7. kimi cost about 13× what Haiku did for that same score.
- **Debris.** One grok session copied Apache's 1,582-line `StringSubstitutor.java` to the repo root while
  investigating, and left it in the result. It is outside any source folder, so the build ignores it, but it would
  have been in the PR.
- **Cross-check (recipe dry run on each agent result):** the recipe would still change something in 39 of 40
  results. The one exception, grok clone5, was a successful dry run with nothing to change, not a failure.
  Mostly that's moving commons-configuration2 and commons-text up to the newest versions, which on this app is the
  change that stops it starting.

**Reading the recipe's row correctly.** The recipe's patch, as shipped, failed: it breaks startup, which in production
is an outage. That is what the board's red recipe row shows, and it is the honest headline. The recipe's code
changes are still correct (the held-at-2.7 build above), and they closed the StAX XXE that 31 of 33 started agent runs
missed. DOM XXE, Text4Shell and Zip Slip work as a canary: every started agent run and the recipe's code fixed them,
which shows the tooling and the probe were working.

### One more line in the prompt: "start the app"

Every startup failure above was invisible to `mvnw verify`, and almost no agent ran the app. So the last round
(2026-10-31) asks for it. The ticket is unchanged except for one added sentence: "Before you finish, build the app
jar (ledger-app) and start it to confirm it actually runs." Six models, five fresh runs each, same harness and probe.
Grok and gemini were left out to fit the month's remaining credits.

Each cell is *without the line → with it*, over the same model's five runs. "Ran the app" is read from the agent's
own transcript: a shell command that runs the jar, or Spring Boot's startup line for the app.

| Model | App starts | Agent ran the app | Chose config2 2.15.1 | All 7 safe | Credits (5 runs) |
|---|---|---|---|---|---|
| claude-sonnet-5.5 | 3 → 5 | 0 → 5 | 2 → 0 | 2 → 1 | 57.4 → 76.8 |
| gpt-5.3-codex | 5 → 5 | 0 → 5 | 0 → 0 | 0 → 0 | 82.6 → 88.5 |
| kimi-k3 | 5 → 5 | 0 → 5 | 0 → 0 | 0 → 0 | 97.5 → 154.0 |
| gpt-6-luna | 5 → 5 | 0 → 5 | 0 → 0 | 0 → 0 | 10.9 → 13.2 |
| mai-code-1.1-flash | 4 → 5 | 0 → 5 | 1 → 0 | 0 → 0 | 9.5 → 9.6 |
| claude-haiku-5.5 | 5 → 5 | 0 → 5 | 0 → 3 | 0 → 0 | 7.4 → 12.4 |
| **all six** | **27 → 30** | **0 → 30** | **3 → 3** | **2 → 1** | **265.3 → 354.5** |

- **The line removed the outage.** Every agent ran the app, and all 30 apps started. As many runs chose 2.15.1 as
  before (three), but this time they were all Haiku runs that hit `ConfigurationDeniedException` themselves and fixed
  it: each changed `LedgerSettings` to read `ledger.properties` from the classpath stream instead of a URL, which
  works inside the Boot jar on the newest version. In one run's words: "Unit tests missed this because they run from
  `file:` paths."
- **It didn't widen the scope.** Both unnamed XXEs stayed open in 27 of 30 runs. Sonnet clone1 closed all seven,
  Sonnet clone5 closed StAX only, and kimi clone2 closed SAX only. Starting the app checks that it runs, not that
  it's safe.
- **It costs more.** About a third more credits over the six models, mostly kimi (+58%), because building, starting
  and probing the app takes more turns.
- **Still no two patches alike.** 30 runs, 30 different patches.

### Two more prompts: name the holes, or look past the ticket

The start-the-app round left one question open. Were the unnamed XXEs missed because the agents couldn't fix them,
or because nobody asked? Two more rounds on 2026-11-02, the same six models, five fresh runs each, both keeping the
start-the-app line:

- **Named holes (the canary).** The ticket also lists the three holes it left out, as findings 6 to 8 with file and
  line: the StAX XXE in `ReportMetadataReader`, the SAX XXE in `AccountListImporter`, and the second SQL injection in
  `AccountRepository.findOverdrawn`.
- **Look past the ticket.** The original five findings plus one generic sentence that names nothing: "The scanner may
  have missed other instances of these same problems. Check the rest of the code for them and fix those too."

Runs with all seven holes closed, of five, and the credits for those five runs:

| Model | Ticket only | + start the app | + named holes | + look past the ticket |
|---|---|---|---|---|
| claude-sonnet-5.5 | 2 · 57.4 | 1 · 76.8 | 5 · 88.2 | 5 · 97.9 |
| gpt-5.3-codex | 0 · 82.6 | 0 · 88.5 | 5 · 152.8 | 5 · 149.3 |
| kimi-k3 | 0 · 97.5 | 0 · 154.0 | 5 · 141.7 | 5 · 209.7 |
| gpt-6-luna | 0 · 10.9 | 0 · 13.2 | 5 · 11.3 | 5 · 13.6 |
| mai-code-1.1-flash | 0 · 9.5 | 0 · 9.6 | 5 · 14.2 | 3 · 17.1 |
| claude-haiku-5.5 | 0 · 7.4 | 0 · 12.4 | 5 · 14.1 | 5 · 18.9 |
| **all six** | **2 of 30 · 265.3** | **1 of 30 · 354.4** | **30 of 30 · 422.4** | **28 of 30 · 506.6** |

- **The gap was scope, not skill.** Named, every hole was closed in every run, by every model, cheap ones included.
  Haiku closed all seven for 14 credits across five runs.
- **One generic sentence got almost all the way.** 28 of 30 runs closed all seven without being told where to look.
  The two misses were MAI runs: clone1 closed the SAX XXE but left StAX open, clone2 the reverse.
- **Looking costs more.** 507 credits for the look-past round against 422 for the named one: the agents had to
  search. kimi went from 142 to 210.
- **Startup held.** All 60 apps started and every agent ran its app. Ten runs chose commons-configuration2 2.15.1,
  hit the startup error, and changed the code so the app starts on it.
- **Still no two patches alike.** 60 runs, 60 different patches, touching 7 to 15 files.

**The lesson for the course:** an agent's reach ends where the prompt's does. Told to start the app, every agent did
and the outages stopped. Told about the missing holes, or just told to look for more, nearly every run closed all
seven. But someone has to know to write those lines, and every run still produced a different patch that has to be
reviewed on its own. The recipe gave the same result every time: here that was the same production break, and the
same three missed holes, every time. That consistency is the point. A recipe bug is found and fixed once, in one
place, and the fix reaches every repo it runs on.

## Deviations from the brief, and harness bugs found along the way

- **Side B ran before Side A.** The recipe left its patch in the clones under the git-ignored `.moderne/` folder. An
  agent could have read it. Fixed by deleting all ignored files and checking the tree is clean before every session.
- **Regression plant failed the first time.** The vets-service pom indents with tabs and the anchor expected spaces.
  The plant now uses a regex anchor, and clone1 was reset before rerunning.
- **The spend guard watched the wrong meter.** Copilot reports premium requests and AI credits. Pro budgets are in
  credits, so the guard now reads credits.
- **The guard's own check ended the panel early.** `[ -n "$stop_after" ] && die` returns 1 under `set -e` when the
  guard hasn't tripped. Changed to an `if`.
- **Models not on the plan.** `gpt-6.1-sol` and `gemini-4-argon` returned "not available" and are skipped.
- **`mod study` matched two tables** for the short name `DependenciesInUse`. It now uses the fully qualified name.
- **The Moderne CLI won't run on a private repo.** For the ledger it said "A valid license is required: this
  repository is not an open source repository", the same wall as Lab 4. Lab 8b's recipe side uses the free
  OpenRewrite Maven plugin with the same recipes.
- **A stale jar fooled me once.** `mvnw package` without `clean` rewrapped the old fat jar, so a version change
  seemed to have no effect. Every build now uses `clean`.
- **The Lab 8 panel cross-checks failed silently.** `crosscheck` assumed the recipe was still in the CLI's catalog. It
  wasn't, and every panel cross-check failed with `Unable to find recipe lab.FixLog4Shell`. The harness treated "no
  patch" as "nothing to change" and wrote empty results. Now it installs the recipe every time, and a failure leaves
  no result and is listed in `crosscheck-failed.txt`. The bad results were deleted, with their logs kept in
  `results/logs/failed-crosscheck-2026-10-30/`, and the cross-checks were rerun.

- **The Lab 8b cross-check had the same silent-failure bug** (`|| echo "dry run failed"`, then an empty patch). It
  hadn't fired: the only empty result, grok clone5, has a `BUILD SUCCESS` log. It's fixed the same way as Lab 8's.
- **Credits don't quite reconcile.** Before the start-the-app round, the harness had logged 1,046 credits across both
  labs, and GitHub's usage page showed 1,086. Grok matches exactly. The gap is mostly 19 credits on GPT-5.6 Terra,
  which never appears in the harness logs, and about 12 extra Sonnet credits, probably from smoke tests before
  logging began. After the round the harness total is 1,400.8, against a Copilot Pro allowance of 1,500 with no
  overage budget.
- **Detecting "the agent ran the app" took two tries.** Matching only a shell line that starts with `java -jar` missed
  agents that wrapped it (`timeout 25s java -jar …`). Matching only Spring Boot's "Started LedgerApplication" line
  missed agents that sent the app's output to a file and then sent it real requests. The board accepts either
  signal. Neither appears in the unit-test output, which prints "Started LedgerApplicationTest". All 30 start-round
  transcripts show it; of the first 40, only gemini clone3.
- **The per-run log line always said "(no probe results)".** Its Python summary used a backslash inside an f-string
  expression, a syntax error before Python 3.12, and the error was hidden. The probe results themselves were always
  written, and the board reads those, so no verdict changed. Fixed on 2026-11-02.
- **The spend guard counts across months.** It adds up every credit in both labs' `spend.log`, so after the monthly
  reset it had to be raised by hand (`BUDGET=2850`: 1,407 spent before plus this month's 1,450).
- **One run was briefly "not available".** gpt-6-luna on named clone5 got "not available" once while every Luna run
  around it worked. The harness skipped it as designed, and it was rerun by itself.
- **An XML comment was read as a version choice.** kimi clone5 wrote "fixed in commons-configuration2 2.8.0+" in a
  pom comment, and the board script listed 2.8.0 next to the 2.10.1 it actually set. Comment lines are now skipped.

## The live board

`lab/board/` holds the data and page behind the private "Agent drift board" artifact. `python3 -I
lab/board/make_board_data.py [--dry-run]` rebuilds the CSVs from the result files, one per prompt variant
(`lab8b-<variant>-runs.csv`). The probe verdicts and spend logs are tracked in git, so a fresh clone rebuilds them. The page's charts read only those
CSVs, and each tab opens with a plain-words "What happened, in order" summary.

## Cleanup

```bash
~/projects/general_chat/moderne.ai/lab/uninstall.sh --dry-run
```

It lists the lab's containers, images, volumes and work folders, and removes only what the lab created. Then revoke
the Copilot token at github.com → Settings → Developer settings → Fine-grained tokens.
