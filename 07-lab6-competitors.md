# Lab 6: Head to head: Moderne/OpenRewrite vs. Microsoft vs. AWS

**Goal:** the Lab 1 job (spring-petclinic, Spring Boot 2.7/Java 8 → Boot 3.5/Java 17) done by the
two big-cloud competitors you have accounts for, scored side by side against the OpenRewrite result.

**Needs:** Docker; a GitHub account with Copilot; optionally AWS credentials (**costs real money, small**).

| Contender | What it is | Uses OpenRewrite? | Cost for this lab |
|---|---|---|---|
| **OpenRewrite** (Lab 1, already done) | Deterministic recipe | It *is* OpenRewrite | $0 |
| **Microsoft `modernize` CLI** (GitHub Copilot app modernization) | LLM agent loop: plan → change → build → fix | **Yes**, Microsoft says it "uses tools like OpenRewrite" | Copilot premium requests on your plan |
| **AWS Transform custom (`atx`)** | LLM agent loop, managed transformations | AWS said "parts of OpenRewrite" in 2023; unverified for `atx` | $0.035 per agent-minute (AWS's own example: Java upgrade of ~17k LOC ≈ 72 min ≈ $2.52). Petclinic is far smaller. |

So this isn't "OpenRewrite vs. AI". It's **"OpenRewrite alone" vs. "OpenRewrite (probably) + an LLM that
builds, tests and repairs."** Fun detail: `modernize` defaults to `--model claude-sonnet-5`.

**Untested by me:** I installed both CLIs and checked their help and setup, but couldn't authenticate either,
so runtimes and results are yours to discover. That's the point of the lab anyway.

## 6.1 Setup (~5 min)

Everything runs in the `moderne-lab-rivals` image (already built): `modernize`, `atx`, `gh`, Node 22,
JDK 8/17/21, Maven. Three identical copies of petclinic at commit `1db99db` are in `lab/rivals/ws/`:

```bash
cd ~/projects/general_chat/moderne.ai/lab/rivals
```

```bash
./score.sh
```

`aws` and `copilot` should read `boot=2.7.0 java=1.8 javax-imports-left=47`; `openrewrite` is the Lab 1 result.

**AWS credentials (only if you're doing AWS).** There's no `~/.aws` on `claude`. Simplest is short-lived
credentials from galena. On **galena**, with a profile that has the `AWSTransformCustomFullAccess` policy:

```bash
aws configure export-credentials --profile YOUR_PROFILE --format env
```

Paste the three `export AWS_...` lines into your shell on **claude**, plus:

```bash
export AWS_REGION=us-east-1
```

`lab6.sh` passes those variables into the container. Nothing is written to disk.

Start the sandbox:

```bash
./lab6.sh
```

**GitHub login** (inside the container, once; it persists in a Docker volume):

```
gh auth login
```

Choose GitHub.com → HTTPS → "Login with a web browser", and open the device URL on galena.

## 6.2 Microsoft: `modernize` (~10–20 min, mostly waiting)

Inside the container:

```
cd /ws/petclinic-copilot
modernize assess --source .
```

Skim the assessment (where does it write it?). Then the actual job, timed:

```
time modernize upgrade "Spring Boot 3.5" --source . --no-tty
```

If it asks which JDK to target, say 17 to match Lab 1. Note how long it took and roughly what it said it was doing.
It typically writes a plan under `.github/modernize/` and commits per task:

```
git log --oneline 1db99db..HEAD
```

## 6.3 AWS: `atx` (optional; ~15–30 min, mostly waiting; run it in parallel)

Open a **second** shell with `./lab6.sh` (same image and volume, separate container) so it can run while
Copilot works. Interactive mode is the safest way to get the target version right:

```
cd /ws/petclinic-aws
atx
```

Then tell the agent:

```
Execute the AWS/java-version-upgrade transformation on /ws/petclinic-aws. Target Java 17 and
Spring Boot 3.5 (javax to jakarta). Build and test with:
mvn -B -Dspring-javaformat.skip=true -Dcheckstyle.skip=true clean verify
```

Watch for: which transformations it lists (`AWS/java-version-upgrade` is the right one;
`AWS/spring-boot-version-upgrade` is for 3.x → 4.x), what it asks you to approve, and the
agent-minutes it reports at the end. That's your bill. It commits each step to git:

```
git log --oneline 1db99db..HEAD
```

The headless equivalent, for reference only (the docs show this shape; I haven't confirmed how to pass the target version):
`atx custom def exec -n AWS/java-version-upgrade -p . -c "mvn clean verify" -x -t`

`exit` both containers when they're done.

## 6.4 Score it (~5 min)

On the host:

```bash
./score.sh --test
```

That prints Boot/Java versions, javax imports left, commits, diff size vs. baseline, and runs the full
test suite on Java 17 for each copy (about 1–2 min each). Fill in the rest yourself:

| | OpenRewrite | Copilot `modernize` | AWS `atx` |
|---|---|---|---|
| Boot / Java reached | 3.5.16 / 17 | | |
| javax imports left | 0 | | |
| Files changed (+/−) | 24 (243/175) | | |
| Tests (41, 1 skipped upstream) | ✅ all pass | | |
| Wall-clock time | ~1 min (warm) | | |
| Cost | $0 | premium requests | $ (agent-min × 0.035) |
| Same result if run again? | yes, byte-identical | ? | ? |
| Explains *why* each change | recipe name per change | plan.md / commits | report |
| Runs on 5,000 repos | Moderne's whole business | `--source repos.json`, cloud delegate | campaigns via web app |

Compare an entity class across all three:

```bash
for t in openrewrite copilot aws; do echo "=== $t"; git -C ws/petclinic-$t diff 1db99db -- src/main/java/org/springframework/samples/petclinic/owner/Owner.java | head -40; done
```

And the scope of what each touched:

```bash
for t in openrewrite copilot aws; do echo "=== $t"; git -C ws/petclinic-$t diff --stat 1db99db | tail -1; done
```

Things to look for: did the LLM tools touch files the recipe didn't (README, Dockerfile, tests)?
Did they make **"helpful" extra changes** you didn't ask for? Did they leave the build green on their own,
or need you to step in?

## 6.5 Security angle (if time)

Microsoft documents built-in CVE fixing for Maven dependencies. Look back at the 6.2 `modernize assess`
output: does it list vulnerable dependencies alongside the migration issues? Compare that list with
Lab 4's `./lab4.sh scan` report. Bonus: point it at the Lab 4 demo repo and see whether **it** knows about
the Claude-found Jetty CVE-2026-19204 that OpenRewrite's data missed. On the host:

```bash
cp -r ../cli/ws/local/ai-found-cves ws/
```

Then inside the container:

```
modernize assess --source /ws/ai-found-cves
``` AWS's `AWS/security-issue-fixer` only fixes findings *you feed it* from a scanner
(SARIF); it doesn't scan on its own.

## 6.6 Takeaways

- **Per-repo migration quality:** probably close. All three lean on OpenRewrite-style transforms; the LLM
  tools add a build-and-repair loop that can fix leftovers a recipe misses. That loop is also what makes them
  slower, costlier and non-deterministic.
- **Where Moderne differs** is not one repo. It's the **estate**: pre-built LSTs for every repo, the same change
  everywhere, data tables proving it, mass PRs. Microsoft and AWS are adding multi-repo (`repos.json`, campaigns),
  so that's the space to watch.
- **Security:** none of the three *discover* new bugs. Lab 4's lesson stands: AI finds, something has to fix
  everywhere, and that something is the product category Moderne is in.

Reset the copies to run again:

```bash
for t in copilot aws; do git -C ws/petclinic-$t reset -q --hard 1db99db && git -C ws/petclinic-$t clean -qfdx; done
```
