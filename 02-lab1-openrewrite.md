# Lab 1: OpenRewrite on one repo (no accounts)

**Goal:** watch a recipe migrate a real app from **Spring Boot 2.7 / Java 8** to
**Spring Boot 3.5 / Java 17**, then prove it still works by running its tests.
This is the free, open-source engine that everything Moderne sells is built on.

**Needs:** Docker (that's all; Java runs in a `maven:3.9-eclipse-temurin-17` container).
I already ran this whole lab once on `claude`, so the Maven cache in `lab/.m2` is warm.
The first dry run took ~4 min cold; it should be about 1 min now.

All commands run from `lab/`:

```bash
cd ~/projects/general_chat/moderne.ai/lab
```

## Step 1: Look at the "before"

The repo is `spring-petclinic` checked out at commit `1db99db` ("Update to Spring Boot 2.7.0").

```bash
./lab1.sh reset
```

```bash
grep -nE '<version>2\.7|<java.version>' spring-petclinic/pom.xml
```

```bash
grep -rn 'import javax' spring-petclinic/src/main/java | head
```

Note the `javax.persistence` / `javax.validation` imports. Spring Boot 3 requires
`jakarta.*`, so a hand migration means touching every entity, plus property renames,
plugin bumps, and the Java version. Hold that thought.

## Step 2: Dry run (changes nothing)

```bash
./lab1.sh dryrun
```

What to notice in the output:

- **The recipe tree.** `UpgradeSpringBoot_3_5` → `3_4` → `3_3` → ... → `3_0` → `UpgradeToJava17` → ...
  Each line says *which* sub-recipe touched *which* file. That's how a composite recipe
  is built: small, tested pieces stacked up.
- **"Estimate time saved."** Their marketing number. Interesting, not gospel.
- **Non-Java files changed too:** `pom.xml`, `build.gradle`, the Gradle wrapper,
  `application.properties`, even `.github/workflows/maven-build.yml`.

Look at the patch:

```bash
git -C spring-petclinic apply --stat target/rewrite/rewrite.patch
```

```bash
less spring-petclinic/target/rewrite/rewrite.patch
```

Things worth finding in `less` (type `/` to search):

- `/jakarta`: the javax→jakarta swap, with import ordering preserved
- `/spring-boot-starter-parent`: the version bump
- `/java.version`: 1.8 → 17
- the entity classes (`Owner.java`, `Pet.java`): see that formatting and comments are untouched. That's the "lossless" in LST.

## Step 3: Apply it

```bash
./lab1.sh run
```

```bash
git -C spring-petclinic diff --stat
```

## Step 4: Prove it

```bash
./lab1.sh test
```

When I ran it: **41 tests, 0 failures, 1 skipped (`CrashControllerTests`, skipped upstream too), BUILD SUCCESS**
on Spring Boot 3.5.16 / Java 17. No hand edits.

## Step 5 (optional): try a different recipe

Any recipe from the [OpenRewrite catalog](https://docs.openrewrite.org/recipes) that lives in `rewrite-spring`
(or its dependencies) works the same way. Reset first, then for example:

```bash
./lab1.sh reset
```

```bash
RECIPE=org.openrewrite.java.spring.boot2.SpringBoot2BestPractices ./lab1.sh dryrun
```

## What you just saw, and what you didn't

- **Saw:** one repo, one recipe, deterministic, type-aware, tests green. **This part is free forever.**
- **Didn't see:** doing this to 3,000 repos with different JDKs and build quirks, knowing which ones
  failed, and getting the PRs merged. That's Lab 2 (CLI) and the Platform.

**Checkpoint:** if "deterministic, type-aware refactoring" now means something concrete to
you, move to Lab 2. Reset the repo when you're done: `./lab1.sh reset`.
