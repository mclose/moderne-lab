# Lab 5 recipe project (OpenRewrite)

A teaching project for writing OpenRewrite recipes with Claude Code.
The vendor skill `.claude/skills/create-recipe` (from Moderne CLI 4.9.1; `./get-skill.sh` copies it in) has the recipe patterns.
Ignore its "Prerequisites" version check: `mod` isn't on the host, and the patterns haven't changed.
**Where it conflicts with this file, this file wins:**

- **Maven, not Gradle.** Build with `./mvn.sh test` / `./mvn.sh install` (Docker, JDK 21). There is no Java on the host; never run `mvn`, `gradle`, or `java` directly.
- **Pinned versions, never `latest.release`.** OpenRewrite releases after Aug 2026 are on the Code Genome Project, which needs a token we don't have. `pom.xml` pins rewrite-bom 8.90.4 and rewrite-java-dependencies 1.60.2 from Maven Central. Don't bump them.
- **No `mod` on the host.** The Moderne CLI lives in the `moderne-lab-cli` Docker image (`../cli/lab2.sh`). To try a recipe on real code, use `./run-on-demo.sh dryRun <recipe.Name>` (runs against `../cli/ws/local/ai-found-cves`).
- Package `lab.security`. YAML recipes go in `src/main/resources/META-INF/rewrite/security.yml`.
- Types from third-party libs in tests: add the lib as a `test`-scoped Maven dependency, then `JavaParser.fromJavaVersion().classpath("<artifactId>")`.
- Recipe `description` must end with a period. Tests: `RewriteTest`, before/after text blocks, plus a no-change test.
- `../recipes-solution/` holds one worked answer (`FindUnsafeRarExtraction`). Don't read it unless asked.
