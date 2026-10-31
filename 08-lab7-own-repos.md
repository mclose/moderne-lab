# Lab 7: Bring your own repo: Python vs. Java

**Goal:** run open-source recipes on code you actually know, in both languages, and see where
Moderne is deep (Java) and where it's catching up (Python, the language most AI agents are written in).

**Needs:** Docker. No account: the CLI is free on **public** repos, and both repos here are public.

**What I used** (swap in your own public repos; nothing below depends on these two):

| Repo | Language | Why |
|---|---|---|
| `mclose/dns-mcp` | Python 3.12, FastAPI + MCP + Pydantic 2 | Matthew's own MCP server: a real agent-era Python app, 17 files |
| `dnsjava/dnsjava` | Java, built for Java 8, Lombok, Maven | The standard Java DNS library: a real, well-maintained codebase, 350 Java files |

Results below are from **2026-10-28 on Moderne CLI 4.12.0**. Recipe output changes between releases.

## 7.0 Setup (~5 min)

This lab has its own folder, `lab/own/`, so Lab 2 stays untouched. The launcher `own.sh` uses the
`moderne-lab-own` image (the Lab 2 image plus Python 3, which the CLI needs to parse Python). It shares
the CLI home volume with Lab 2 and **caps the container at 1.5 CPUs**: LST builds peg every core you give them.

```bash
cd ~/projects/general_chat/moderne.ai/lab/own
```

```bash
git -C ws clone https://github.com/mclose/dns-mcp.git
```

```bash
git -C ws clone https://github.com/dnsjava/dnsjava.git
```

(Skip both if `ws/` already has them.)

```bash
./own.sh
```

Everything below runs **inside the container**, in `/ws`.

## 7.1 Python: dns-mcp (~10 min)

```
mod build ./dns-mcp
```

About 15 s. The CLI parses Python by default since 4.3, given Python 3.12+ on the PATH.

Install the open-source Python recipes. **Note the versions:** the pip package is current on PyPI, but the two
JARs stopped at Maven Central's last release (August 2026; newer ones are behind the Code Genome token):

```
mod config recipes pip install openrewrite-migrate-python==0.18.0
mod config recipes jar install org.openrewrite.recipe:rewrite-migrate-python:0.13.0
mod config recipes jar install org.openrewrite:rewrite-python:8.90.4
```

That mix worked for everything below. See what you got:

```
mod config recipes search python --json=id
```

Now two runs. `mod run` is always a dry run; it writes a patch and changes nothing.

```
mod run ./dns-mcp --recipe=org.openrewrite.python.migrate.UpgradeToPython314
```

```
mod run ./dns-mcp --recipe=org.openrewrite.python.cleanup.PythonBestPractices
```

What I got:

- **`UpgradeToPython314`** (30 s): `requires-python = ">=3.12"` → `">=3.14"` in `pyproject.toml`, and
  `FROM python:3.12-slim` → `3.14-slim` in the `Dockerfile`. It **did not** touch
  `.github/workflows/ci.yml`, which still says `python-version: "3.12"`. Apply this as-is and CI would test
  on a Python the package no longer allows. That's a reviewer catch.
- **`PythonBestPractices`** (20 s): 2 files, both genuine readability fixes:
  `name.startswith("_") or name.startswith("print_")` → `name.startswith(("_", "print_"))`, and an `else:` after
  a `return` removed (de-indenting a whole nested function in `tracking.py`).

Now the agent-stack recipes. dns-mcp is already on Pydantic 2.13, so this one checks it's current:

```
mod run ./dns-mcp --recipe=org.openrewrite.python.migrate.pydantic.UpgradeToPydantic212
```

No changes: dns-mcp is already current. `org.openrewrite.python.codequality.CodeQuality` also came back clean.
A recipe that finds nothing is a useful result too: it's a check you can run on every repo, every week.

**What's in the free Python catalog** (installed above, 271 recipes): Python 3.8 → 3.15 upgrades (most of it),
cleanup and code quality, dependency changes in `pyproject.toml`, and a few **agent-stack** migrations:
**LangChain 0.2 / 1.0**, **Pydantic 2.10–2.12**, **pandas 2.0**. What's missing for this repo is the `mcp` 1 → 2
migration (2.0 removed `mcp.server.fastmcp`, which is why dns-mcp pins `mcp<2`). Nobody has written that recipe.
Lab 5 shows how you would.

## 7.2 Java: dnsjava (~15 min, mostly waiting)

```
mod build ./dnsjava
```

About 2 minutes on 1.5 CPUs: it runs Maven to resolve every dependency, so the tree knows every type.

Three runs. Each takes under a minute because the LST is already built:

```
mod run ./dnsjava --recipe=org.openrewrite.java.migrate.UpgradeToJava21
```

```
mod run ./dnsjava --recipe=org.openrewrite.staticanalysis.CommonStaticAnalysis
```

```
mod run ./dnsjava --recipe=org.openrewrite.java.dependencies.DependencyVulnerabilityCheck
```

**`UpgradeToJava21`: 128 files, +619/−496.** The CLI's "time saved" estimate: 13 h 27 m. Looking closer:

- **Real modernization:** `list.get(list.size() - 1)` → `list.getLast()`; `if (e instanceof X) throw (X) e;` →
  `if (e instanceof X ex) throw ex;`; switch expressions; Maven `<source>/<target>` → `<release>`; plugin bumps.
- **Noise:** **98 of the 128 files** only gain `import org.xbill.DNS.Record;` inside package `org.xbill.DNS`.
  Java 16 added `java.lang.Record`, and the recipe guards against the name clash. But a same-package class already
  wins over `java.lang`, so these imports change nothing. They do triple the review.
- **An inconsistency:** it bumps the `lombok.version` property to 1.18.48, then adds Lombok annotation-processor
  paths with a hard-coded **1.18.40**.
- **It doesn't compile.** Apply the patch and `mvn compile` gives **50 errors**
  (`pattern matching in instanceof is not supported in -source 8`). dnsjava sets its target through its own property,
  `<target.jdk>8</target.jdk>`. The recipe rewrote the code for Java 21 but didn't recognize that property, so the
  build still targets 8. Set `-Dtarget.jdk=21` and it compiles, and the full suite passes: **2,193 tests, 0 failures** (29 skipped
  upstream), about 1.5 minutes. So the code changes were right; one build property was the gap.

To check it yourself, from the host (`lab/own`). Replace RUN_ID with the folder name `mod run` printed:

```bash
git -C ws clone -q dnsjava dnsjava-j21 && git -C ws/dnsjava-j21 apply ../dnsjava/.moderne/run/RUN_ID/fix.patch
```

```bash
./own.sh bash -lc 'cd dnsjava-j21 && mvn -B -q -DskipTests -Dspotless.skip -Danimal.sniffer.skip -Dcheckstyle.skip compile'
```

Then again with `-Dtarget.jdk=21` added after `mvn -B -q`.

**`CommonStaticAnalysis`: 60 files, +210/−174.** Mostly fine (`= null` / `= 0` field initializers removed,
missing `break`s added, redundant parentheses). But it also makes public classes `final` and public constructors
`protected` (`public class SIG0` → `public final class SIG0`). In an application that's tidy. **In a published library
it's a breaking API change** for anyone who subclasses them. The recipe can't tell an app from a library.

**`DependencyVulnerabilityCheck`: nothing.** dnsjava's dependencies are clean against the (August) advisory data.
That's the right answer, and also the Lab 4 caveat: clean *as of that data*.

**And for the record, the deeper point:** dnsjava *deliberately* builds for Java 8; the `pom.xml` says so in comments
("Stay on 4.x for Java 8 compatibility"). Upgrading it to 21 would drop its Java 8–17 users. The recipe is mechanically
right and strategically wrong. Deciding *whether* to run a migration is the human (or agent) part.

## 7.3 Java vs. Python, side by side

| | Java (dnsjava) | Python (dns-mcp) |
|---|---|---|
| LST build | 2 min, needs Maven + JDK to resolve types | 15 s, needs Python 3.12+ |
| Free catalog (as installed here) | ~900 recipes: Java 8 → 25, Spring Boot 2 → 3 → 4, javax → jakarta, JUnit 4 → 5, logging, security, static analysis | ~270: Python 3.8 → 3.15, cleanup, deps, LangChain, Pydantic, pandas |
| Biggest migration it ran | 128 files, real API rewrites (and real gaps) | 2 config lines |
| What you have to check | Build config it didn't understand, noise, library vs. app | CI config it didn't touch |
| Where Moderne's paid tier adds the most | Estate-wide runs, the Platform, newer recipe releases | Same; some Python recipes in Moderne's docs are marked Moderne-only |

The honest summary: **Java is where Moderne is deep**, because that's where enterprises have 20 years of code
and big framework migrations. **Python support is real and growing toward the agent stack** (LangChain, Pydantic),
but the recipes are smaller and the payoff per run is lower. If agents are mostly written in Python, the code
they *maintain* in an enterprise is still mostly Java. That's the bet Moderne is making.

## 7.4 Biggest bang for the buck: Java recipes for a distributed workforce

If an enterprise with teams on several continents bought this for one recipe family, it would be **version migrations**:

1. **Java LTS upgrades** (`UpgradeToJava17`, `UpgradeToJava21`): every repo, same change, same way, regardless
   of which team or vendor owns it. This is the classic "6 months of offshore tickets" project.
2. **Spring Boot 2 → 3** (Lab 1), which drags in **javax → jakarta**. The single most-cited Moderne use case.
3. **JUnit 4 → 5** and **logging framework** moves: boring, enormous, perfect for recipes.
4. **Dependency vulnerability remediation** (Lab 4): the security team's version of the same idea.

What makes it work across a distributed workforce isn't the per-repo diff (an LLM can do one repo).
It's that **every repo gets the identical, reviewable change, labelled with the recipe that made it**, so a
reviewer in any time zone checks "is this the `UpgradeToJava21` change?" instead of reading 128 hand-made diffs.
This lab also showed the catch: you still need someone who knows the build (dnsjava's `target.jdk`) and the product
(library vs. app) to decide what to run and to finish the last 5%.

## 7.5 Optional: a fintech-flavoured third repo (untested)

For a financial-services audience, two public Java codebases fit better than a DNS library:

| Repo | What it is | Why it's interesting here | Cost on 2 cores |
|---|---|---|---|
| `JavaMoney/jsr354-ri` (Moneta) | Reference implementation of the Java Money and Currency API | Money handling is in every fintech app. Java 11 with a standard `maven.compiler.release` (contrast with dnsjava's custom property), **TestNG** tests | Small (6 MB), a few minutes |
| `quickfix-j/quickfixj` | FIX protocol engine | FIX is how brokerages route orders. Java 8, **JUnit 4 tests on the vintage engine**, so `org.openrewrite.java.testing.junit5.JUnit4to5Migration` should have real work | Heavy: generates thousands of FIX message classes |

The recipes to try: `UpgradeToJava21` on both, and from `rewrite-testing-frameworks` (Maven Central 3.44.0)
the JUnit 4 → 5 migration on QuickFIX/J. Clone them into `ws/` the same way as 7.0.

The pattern behind this: large financial firms commonly run Java EE-era stacks (WebLogic, Struts) next to newer
containerized services, with Java APIs under whatever the web front end is. Struts → Spring, javax → jakarta and
app server → Spring Boot are the migrations those estates need, and OpenRewrite has recipe modules for them
(e.g. `rewrite-struts`, `rewrite-spring`).

## 7.6 Reset

The runs changed nothing in the repos. Remove the compile-test copy and run artifacts:

```bash
rm -rf ws/dnsjava-j21 ws/*/.moderne/run
```

**Checkpoint:** you can say where Moderne is strong (Java estates, framework migrations), where it's thin (Python
framework migrations, your own build quirks), and why "the recipe ran" isn't the same as "the build is green".
