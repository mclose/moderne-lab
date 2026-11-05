# Demo: one migration, one finding (for a slide)

**Goal:** a short, repeatable demo that shows the two things Moderne claims: changes that are
**deterministic** (same input, same patch, byte for byte) and **idempotent** (run it again on the result, nothing changes),
plus a security finding in a file most people never look at. Everything here is open source and public.

**Needs:** Docker and the `moderne-lab-cli` image from Lab 2. No account. ~7 min on a 2-core box, mostly waiting.

**Target:** [`spring-petclinic/spring-petclinic-microservices`](https://github.com/spring-petclinic/spring-petclinic-microservices),
`main` at `e8b747a` (2026-10-23): 8 Spring Boot 4 services, Maven, Java 17.

Results below are from **2026-10-28 on Moderne CLI 4.12.0**, `rewrite-migrate-java` as installed in Lab 2,
`rewrite-github-actions` 3.29.0. I ran it twice: by hand, then with `demo.sh`. Both runs gave the same results.

## The whole thing in one command

```bash
~/moderne-lab/lab/cli/demo.sh
```

It stops at the first failure and prints the log tail. Full logs, patches and clones go to `lab/cli/ws/demo/`.
Start over with `./demo.sh reset`, which deletes that folder.

The steps below are what the script does, so you can run them one at a time in `./lab2.sh` instead.

## Run 1: `org.openrewrite.java.migrate.UpgradeToJava21`

In the container, from a fresh clone of `main`:

```
mod build .
```

`✓ Maven · JDK 17.0.20.1-tem (1m 41s)`. The CLI picked JDK 17 because that's what the pom targets.

```
mod run . --recipe org.openrewrite.java.migrate.UpgradeToJava21
```

```
1m 41s saved by using previously built LSTs
20m saved by using recipes
Produced results for 1 repository.
MOD SUCCEEDED in 37s
```

The patch is at `.moderne/run/<id>/fix.patch`: **4 files, +7/−7.**

> **Don't put the preview on a slide.** While it runs, the CLI prints `... (64 more files not shown)`.
> That number doesn't match the 4-file patch. Count `diff --git` lines in `fix.patch` instead.

**What changed.** Customers, vets and visits had nothing to migrate.

| File | Change |
|---|---|
| `pom.xml` (root) | `<java.version>17</java.version>` → `21` |
| `docker/Dockerfile` | both `FROM eclipse-temurin:17` → `21` (a non-Java file) |
| `api-gateway/.../VisitsServiceClientIntegrationTest.java` | `.get(0)` → `.getFirst()` ×3 (Java 21 `SequencedCollection`) |
| `genai-service/.../AIDataProvider.java` | `.get(0)` → `.getFirst()` |

Use this hunk to show formatting is left alone: only the calls change. Indentation, blank lines and the neighbouring
`size()` line come through byte for byte.

```diff
@@ -47,9 +47,9 @@ org.openrewrite.java.migrate.UpgradeToJava21
 
     private void assertVisitDescriptionEquals(Visits visits, int petId, String description) {
         assertEquals(1, visits.items().size());
-        assertNotNull(visits.items().get(0));
-        assertEquals(petId, visits.items().get(0).petId());
-        assertEquals(description, visits.items().get(0).description());
+        assertNotNull(visits.items().getFirst());
+        assertEquals(petId, visits.items().getFirst().petId());
+        assertEquals(description, visits.items().getFirst().description());
     }
 
     private void prepareResponse() {
```

### Deterministic: same input, same patch

Clone `main` again into a different folder, `mod build`, `mod run` the same recipe, and hash both patches:

```
8456b8ed89cf7782528f65fe0c4f1fd9f17db15372f746d777440f383c283235  run1.patch
8456b8ed89cf7782528f65fe0c4f1fd9f17db15372f746d777440f383c283235  run2.patch
```

Identical (`cmp` agrees). I got the same hash from all four clones over the two runs.

### Idempotent: run it again on the result

```
git switch -c java21 && mod git apply . --last-recipe-run
```

`4 files changed, 7 insertions(+), 7 deletions(-)`. **Then rebuild the LST before rerunning:**

```
mod build .
mod run . --recipe org.openrewrite.java.migrate.UpgradeToJava21
```

> **Gotcha:** `mod run` works on the LST, not on the files. If you skip `mod build`, the rerun
> uses the old Java 17 tree and gives you the same patch again, which looks like the recipe isn't idempotent.
> With the rebuild, the build log shows `✓ Maven · JDK 21.0.12.1-tem`: the CLI now sees a Java 21 project.

The rerun gives `Produced results for 1 repository.` / `MOD SUCCEEDED in 18s` and **writes no `fix.patch` at all**.
No `Update(...)` blocks either. That's the empty patch.

### It still builds

```
./mvnw -q verify
```

On the `java21` branch with `openjdk version "21.0.12.1"`, it **passes** (exit 0). All 8 modules build, and 20 tests run
with 0 failures (api-gateway 9, customers 7, config/discovery/vets/visits 1 each).
`admin-server` and `genai-service` have no tests, so the `AIDataProvider` change is only checked by compiling.

## Run 2: `org.openrewrite.github.security.UnpinnedActions`

This recipe isn't in the Lab 2 set, so install it first:

```
mod config recipes jar install org.openrewrite.recipe:rewrite-github-actions:RELEASE
```

You get 3.29.0 with 56 recipes. Without it, the run fails with `Unable to find recipe org.openrewrite.github.security.UnpinnedActions`.

```
mod run . --recipe org.openrewrite.github.security.UnpinnedActions
```

`MOD SUCCEEDED in 17s`. It's a search recipe: it marks lines and changes nothing. **5 findings**, each with
`ℹ Action '…' is not pinned to a commit SHA. Consider pinning to a specific commit for security and reproducibility.`

| File | Line | Action@ref |
|---|---|---|
| `.github/workflows/check-pr-template.yml` | 24 | `actions/github-script@v7` |
| `.github/workflows/check-pr-template.yml` | 40 | `actions/github-script@v7` |
| `.github/workflows/check-pr-template.yml` | 233 | `actions/github-script@v7` |
| `.github/workflows/maven-build.yml` | 21 | `actions/checkout@v4` |
| `.github/workflows/maven-build.yml` | 23 | `actions/setup-java@v4` |

That's every `uses:` line in the repo (`grep` agrees). Why it matters: a tag like `@v4` can be moved to different code,
but a commit SHA can't. Pinning to a SHA is the standard fix for the supply-chain attacks that hit GitHub Actions.
Note that the Java 21 recipe didn't touch `java: [ '17' ]` in `maven-build.yml`. CI would still build on 17.

## What to say on the slide

- **Deterministic:** two separate checkouts give the same SHA-256 for the patch.
- **Idempotent:** after the migration, the recipe has nothing left to change.
- **Scoped:** 4 files, 7 lines. Pom, Dockerfile and Java API all changed, and nothing else moved.
- **Verified:** `mvnw verify` passes on JDK 21.
- **Beyond Java:** the same engine reads GitHub workflow YAML and finds 5 unpinned actions.

**Checkpoint:** you can run the demo, explain why the LST has to be rebuilt before the rerun, and say what the
demo doesn't show: the tiny diff means this repo was already modern, and the recipe left the CI matrix on 17.
