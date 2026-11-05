# Lab 5: AI-assisted recipe authoring

**Goal:** have Claude Code write an OpenRewrite recipe *with tests*, run it on real code, and see
Moderne's own AI tooling for recipe authoring. The pattern to take away:
**use AI once to write the recipe, then the recipe runs on 10,000 repos without AI.**

**Needs:** Docker, Claude Code. Optional 5.4 needs your app.moderne.io login from Lab 3.

The project is `lab/recipes/`, a small Maven recipe library I set up and tested:

| What | Where |
|---|---|
| The Jetty CVE-2026-19204 recipe from Lab 4 (declarative YAML) | `src/main/resources/META-INF/rewrite/security.yml` |
| Its tests | `src/test/java/lab/security/JettyCve202619204Test.java` |
| Moderne's `create-recipe` skill for Claude Code (from CLI 4.9.1, I read it: patterns and examples, nothing executable). It's Moderne's, so it isn't in this repo: `./get-skill.sh` copies it from your Lab 2 CLI install | `.claude/skills/create-recipe/SKILL.md` |
| House rules for Claude: Docker builds, pinned versions | `CLAUDE.md` |
| Build/test in Docker (JDK 21) | `./mvn.sh test`, `./mvn.sh install` |
| Run a recipe on the Lab 4 demo repo | `./run-on-demo.sh dryRun <recipe>` |
| One worked answer for 5.2 (don't peek) | `lab/recipes-solution/` |

> **Why not Moderne's official `rewrite-recipe-starter`?** I cloned it (`lab/recipe-starter/`, worth
> reading). It won't build without a Code Genome Project token: OpenRewrite releases after Aug 2026
> are no longer on Maven Central. This project pins the last Central versions. Moderne's skill also
> assumes Gradle and `latest.release`, so `CLAUDE.md` overrides that. **That's a real-world lesson
> too: vendor AI skills plus your local constraints.**

## 5.1 Anatomy of a recipe (look, then run)

```bash
cd ~/moderne-lab/lab/recipes
```

```bash
cat src/main/resources/META-INF/rewrite/security.yml
```

```bash
less src/test/java/lab/security/JettyCve202619204Test.java
```

The test is the important part: **before → after** text, plus a **no-change** case (`cannotFixJetty11`).
In OpenRewrite the test *is* the spec.

```bash
./mvn.sh test
```

Expect `Tests run: 2, Failures: 0`. The first run takes about 30 s; Maven's cache is warm.

Three ways to write a recipe, simplest first:

1. **Declarative YAML:** compose existing recipes with options (what you just saw).
2. **Refaster:** `@BeforeTemplate` / `@AfterTemplate` Java snippets, compiled into a recipe.
3. **Imperative Java:** a visitor over the LST (full power; what 5.2 uses).

## 5.2 Have Claude write one

Open a **new** terminal (or tmux pane) and start Claude Code *in the recipe project*, so it picks up
`CLAUDE.md` and the Moderne skill:

```bash
cd ~/moderne-lab/lab/recipes && claude
```

Paste this prompt:

```
Write an OpenRewrite search recipe lab.security.FindUnsafeRarExtraction that marks every call to
com.github.junrar.Junrar.extract(..) (the sink for CVE-2026-28208) with a SearchResult explaining why.
Type-aware: a different class's method named extract must NOT be marked. Write RewriteTest tests
first: one positive case, one look-alike negative case. Make ./mvn.sh test pass, then ./mvn.sh install
and show me ./run-on-demo.sh dryRun lab.security.FindUnsafeRarExtraction.
```

What to watch for while it works:

- Does it use the **create-recipe** skill? Claude Code should say it's loading it.
- Does it write tests **before** the recipe, and does it hit the "junrar types aren't on the test classpath" problem
  (and solve it with `JavaParser...classpath("junrar")`)? That's the classic first-recipe stumble.
- Does it follow `CLAUDE.md` (Docker Maven, pinned versions) or drift toward the skill's Gradle advice?

**Done when** the dry run shows this in `src/main/java/lab/Unpack.java` of the demo repo:

```
/*~~(...your message...)~~>*/Junrar.extract(new File(args[0]), new File(args[1]));
```

That `/*~~(...)~~>*/` marker is how search recipes report. On the Moderne Platform the same
markers become the search-results UI and data tables across every repo.

Compare with my answer:

```bash
diff -ru src ../recipes-solution/src
```

## 5.3 Stretch: compose a "security baseline" (5 min)

Same Claude session:

```
Add a declarative recipe lab.security.Baseline to security.yml that runs, in order:
org.openrewrite.java.dependencies.DependencyVulnerabilityCheck, our JettyCve202619204,
org.openrewrite.java.security.search.FindSqlInjection, and our FindUnsafeRarExtraction. Add rewrite-java-security as a
dependency (pinned, from Maven Central). Test it, install it, dry-run it on the demo repo.
```

This is how an org ships *policy*: one named recipe that bundles "what secure looks like here",
versioned like code, and run on every repo.

Optional harder one: ask Claude to write a recipe that fixes the `Register.java` SQL injection that
`FixSqlInjectionConcat` missed in Lab 4.3. See how far it gets. That's the gap between an LLM
*fixing one file* and an LLM *writing a general, tested transformation*.

## 5.4 Moderne's web side (optional, needs your app.moderne.io login)

**I couldn't test these without an account.** Treat them as guided exploration:

1. **Recipe Builder.** On app.moderne.io, look for **Builder** in the left sidebar. It composes *existing*
   catalog recipes and options into a new declarative recipe; it doesn't write custom code and isn't AI.
   - Build `lab.security.Baseline` by clicking: add *Find and fix vulnerable dependencies* + *Find and
     fix SQL injection* (or similar).
   - Use the recipe menu → **copy/download as YAML**. Compare it with the YAML Claude wrote in 5.3. Same format.
   - Try **Import from YAML** with your `security.yml`. It'll accept the parts built from catalog
     recipes; your *Java* recipe won't exist there. That's the line between Builder and code.
   - Dry-run it on the **Legacy Java Apps** org.
2. **Moddy** (the platform's AI agent) is restricted beta and needs a configured tenant. Don't expect it on a
   free account.
3. **Moderne's MCP server** lets Claude Code search and run Platform recipes. It needs a personal access token,
   and I couldn't confirm the public tenant allows it. Docs:
   [agent tools: MCP](https://docs.moderne.io/user-documentation/agent-tools/mcp/getting-started).

## 5.5 Takeaways

- AI is good at the *tedious* part of recipe authoring: LST visitor boilerplate, test scaffolding, the
  classpath gotchas. The **tests** are what make its output trustworthy, which is why the prompt demands them.
- The output is a **deterministic artifact**. Review it once, then run it everywhere, forever, at zero
  LLM cost and zero variance. Compare Lab 6, where the AI runs *every time*.
- Moderne's AI story here is mostly "skills + MCP for your agent". The Builder is a no-code composer, not an AI author.

**Checkpoint:** you've written (well, supervised) a tested security recipe and run it. → Lab 6.
