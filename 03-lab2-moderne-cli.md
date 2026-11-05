# Lab 2: The Moderne CLI across many repos

**Goal:** do what Lab 1 did, but to a *set* of repos at once, then ask questions of the whole
set and get spreadsheets back. This is Moderne's actual product surface; the Platform is
this plus their servers and a UI.

**Needs:** Docker. No account: the CLI is free on public repos.
Everything runs in the `moderne-lab-cli` image (CLI + JDK 8/11/17/21 + Maven), which is already built.

> **The CLI updates itself.** Its wrapper pins `version=RELEASE`, so the first command after a new
> release downloads it (4.9.1 when I built this; 4.11.1 on 2026-10-27; 4.12.0 on 2026-10-28). Expect a download bar once.
> **Gotcha found on the update:** 4.11.1 refuses a *whole* `mod run` if any repo in the folder isn't public.
> Keep private repos out of the working set (that's why Lab 4's demo repo lives in `/ws/local`, not `/ws/repos`).

**The repos** (`lab/cli/repos.csv`), three of the five in Moderne's own "Legacy Java Apps" sample set:

| Repo | Why it's here |
|---|---|
| `CSPF-Founder/JavaVulnerableLab` | Deliberately vulnerable Java 7 webapp. SQL built by string concat, ancient MySQL driver. |
| `rrd4j/rrd4j` | Ordinary mid-size Maven library. |
| `spring-projects/spring-petclinic` (main) | Modern Gradle + Spring Boot 4 app. Already up to date, so it changes the least. |

I already cloned these and built their LSTs, so you can skip the slow step. You can rebuild
them yourself if you want to watch it (Step 2).

## Step 0: Get into the container

```bash
~/moderne-lab/lab/cli/lab2.sh
```

You're now `lab@...:/ws` with the `mod` CLI on the PATH. Everything below runs **inside the container**.
`/ws` is `lab/cli/ws` on the host, so you can open results from outside too.

```bash
mod --version
```

```bash
mod config java installation list
```

That second list is the point: Moderne needs the *right* JDK for each repo because it compiles
each one to get types. Multiply that by 5,000 repos with different JDKs and build quirks; that's the
problem they sell a solution to.

## Step 1: Recipes and repos (already done; look, don't run)

What I ran to set this up:

```
mod git sync csv ./repos /lab/repos.csv --with-sources
mod config recipes jar install org.openrewrite:rewrite-java:RELEASE \
  org.openrewrite.recipe:rewrite-java-security:RELEASE \
  org.openrewrite.recipe:rewrite-migrate-java:RELEASE \
  org.openrewrite.recipe:rewrite-static-analysis:RELEASE
```

See what's installed:

```bash
mod config recipes list
```

```bash
mod config recipes search "java 21"
```

## Step 2 (optional, ~3 min on this box): Build the LSTs

```bash
mod build ./repos
```

When it's done, check which build tool each repo was parsed with:

```bash
grep -h -m1 'Build tool' repos/*/*/.moderne/build/*/build.log
```

You want `Maven` / `Gradle`. **Gotcha I hit building this lab:** my first image had no Maven
installed, and the CLI didn't fail. It silently fell back to `ResourceBuild`, which parses the
files *without the classpath*. Recipes then quietly found nothing (zero vulnerabilities in a
deliberately vulnerable app). LST fidelity is everything, and it's the first thing to check in a
real evaluation.

## Step 3: Which repos have vulnerable dependencies?

```bash
mod run ./repos --recipe org.openrewrite.java.dependencies.DependencyVulnerabilityCheck
```

```bash
mod study ./repos --last-recipe-run --data-table VulnerabilityReport
```

`mod study` writes a CSV and an `.xlsx`; the path is printed above. A quick view without Excel:

```bash
cut -d, -f2,5-8 $(ls -t repos/.moderne/run/*/datatables/*VulnerabilityReport.csv | head -1) | grep -v '^#' | column -ts, | less -S
```

When I ran it: **33 CVE rows** (32 on CLI 4.12.0) across the set (e.g. `mysql-connector-java 5.1.26` in JavaVulnerableLab
with 8 CVEs, `org.json 20090211`, and a few in petclinic). This is the "estate-wide report for the CISO" use case.

## Step 4: Find a code pattern across every repo, type-aware

Every call to `java.sql.Statement.execute*` (the raw-JDBC calls where SQL injection lives):

```bash
mod run ./repos --recipe org.openrewrite.java.search.FindMethods -PmethodPattern="java.sql.Statement execute*(..)"
```

```bash
mod study ./repos --last-recipe-run --data-table MethodCalls --json sourceFile,method | less -S
```

35 hits when I ran it. Look for the one in `LoginValidator.java`:
`"select * from users where username='"+user+"' and password='"+pass+"'"`. A textbook SQL injection.

Why this beats `grep`: it matched on the **type** `java.sql.Statement`, not the variable name.
It finds `stmt.`, `st.`, `this.statement.`, and calls through subclasses, and ignores some unrelated
`execute()` method.

## Step 5: Migrate all three repos to Java 21

```bash
mod run ./repos --recipe org.openrewrite.java.migrate.UpgradeToJava21
```

The CLI prints sample diffs as it goes. Then apply the patches to the working trees:

```bash
mod git apply ./repos --last-recipe-run
```

```bash
for d in repos/*/*; do echo "== $d"; git -C $d diff --stat | tail -1; done
```

When I ran it: JavaVulnerableLab 5 files, rrd4j 27 files, petclinic 2 files. Worth a look:

```bash
git -C repos/CSPF-Founder/JavaVulnerableLab diff
```

Note it bumped `maven.compiler.source` 1.7 → 21 **and** the `FROM eclipse-temurin:8-jdk` line in the
Dockerfile. Recipes reach non-Java files too.

In real life the next steps are what the Platform automates (shown, don't run; there's nowhere to push):

```
mod git checkout ./repos -b java21 --last-recipe-run
mod git add ./repos --last-recipe-run
mod git commit ./repos -m "Upgrade to Java 21" --last-recipe-run
mod git push ./repos --last-recipe-run -u
mod exec ./repos --last-recipe-run -- gh pr create --fill
```

Undo the changes:

```bash
for d in repos/*/*; do git -C $d checkout -- . ; done
```

## Step 6: The paywall

```bash
mod search ./repos implements:Serializable
```

> `A valid license is required to use mod search.`

That's **Trigrep**, the LST-indexed semantic code search they launched in 2026 for AI agents. It's one
of the lines between "free on public repos" and "paid." So are running any of this on private repos,
proprietary recipes, Prethink, and `mod claude chat` / `mod copilot chat` against a tenant.

Leave the container with `exit`.

## Optional: connect to the public tenant

If you created an account in Lab 3, you can make an access token in app.moderne.io
(look for **Access tokens** under your profile/settings) and log the CLI in. **I haven't tested this path; I had no token.**
It's where `mod git sync moderne . --organization "Legacy Java Apps" --with-sources` (pre-built LSTs,
no `mod build`) and the agent-chat features live:

```bash
mod config moderne edit https://app.moderne.io
```

```bash
mod config moderne login --with-token
```

**Checkpoint:** you've now seen the product: one engine, many repos, reports out, patches out.
What the Platform adds is "someone else keeps the LSTs fresh for 10,000 repos, plus a UI and PR automation."
