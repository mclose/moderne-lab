# Moderne crash course

Two tracks: **why anyone pays for this**, then **watch it work**. Do them in order.
You set the pace. Each part ends with a checkpoint; stop whenever you've got what you need.

| # | Part | Type | Needs |
|---|------|------|-------|
| 1 | [The pitch](01-the-pitch.md) | read | nothing |
| 2 | [Lab 1: OpenRewrite on one repo](02-lab1-openrewrite.md) | hands-on, terminal | Docker on `claude` |
| 3 | [Lab 2: Moderne CLI across many repos](03-lab2-moderne-cli.md) | hands-on, terminal | Docker on `claude` |
| 4 | [Lab 3: the Platform in a browser](04-lab3-platform.md) | hands-on, browser (optional) | GitHub login |
| 5 | [Lab 4: Security view: AI-found CVEs](05-lab4-security.md) | read + hands-on | Docker |
| 6 | [Lab 5: AI-assisted recipe authoring](06-lab5-recipe-authoring.md) | hands-on with Claude Code | Docker, Claude Code (5.4: app.moderne.io login) |
| 7 | [Lab 6: vs. Microsoft and AWS](07-lab6-competitors.md) | hands-on, 30–45 min | GitHub Copilot; AWS creds optional (~$ small) |
| 8 | [Lab 7: bring your own repo, Python vs. Java](08-lab7-own-repos.md) | hands-on, ~30 min | Docker; any public repos |
| 9 | [Demo: one migration, one finding (for a slide)](09-demo-slide.md) | one script, ~7 min | Docker (Lab 2 image) |
| 10 | [Lab 8: one security fix, agents vs. a recipe](10-lab8-agent-vs-recipe.md) | scripted, unattended, hours | Docker; GitHub Copilot (personal Pro is enough) |

If you're short on time: Part 1 + Lab 1 gets you the core idea. Lab 2 shows the product.
Lab 3 is optional; it shows the paid UI and needs you to grant GitHub permissions.
Labs 4–6 were added on day 2: security, recipe authoring, competitors. Lab 7 (your own repos, Python vs. Java) on 2026-10-28.
Lab 8 (agent drift vs. a recipe, with an exploitable toy app in 8b) on 2026-10-30.

## The arc

1. **Pitch:** OpenRewrite (free) rewrites code using a type-aware tree. Moderne (paid) makes
   that work across thousands of repos: building the trees, running recipes everywhere,
   reporting, and opening the PRs. In 2026 they pitch it as the "deterministic layer" under AI coding agents.
2. **Lab 1:** one repo, one recipe: Spring Boot 2.7/Java 8 → 3.5/Java 17, tests stay green.
3. **Lab 2:** the `mod` CLI on three repos at once: build LSTs, find vulnerable deps, export
   a spreadsheet, migrate all three to Java 21, semantic code search.
4. **Lab 3:** the same thing on Moderne's servers, with a UI and pre-built LSTs.
5. **Lab 4:** 2026's AI-found CVEs (Claude Mythos / Glasswing). The scanner fixes the ones it knows
   about and **misses the one Claude found**; you close the gap with a 7-line recipe. Then code-level
   SQL-injection fixes and their limits.
6. **Lab 5:** Claude Code writes a tested OpenRewrite recipe using Moderne's own `create-recipe` skill;
   you run it on real code. AI once, then the recipe runs everywhere.
7. **Lab 6:** the Lab 1 migration done by Microsoft's `modernize` (Copilot) and AWS Transform `atx`,
   scored against OpenRewrite.
8. **Lab 7:** your own public repos: a Python MCP server and the dnsjava library. Python works and reaches into
   the agent stack (LangChain, Pydantic); Java is where the depth is, and where a 128-file migration still
   needs a human to fix one build property.
9. **Demo:** `UpgradeToJava21` on spring-petclinic-microservices. Two checkouts give the same patch hash, the rerun is
   empty, and `mvnw verify` passes on 21. Then `UnpinnedActions` finds 5 tag-pinned GitHub Actions.
10. **Lab 8:** the same Log4Shell fix asked of Copilot agents 40 times on 8 models: six different fixes, all green. The
   recipe gives one patch every time. Lab 8b hands agents a scanner ticket for an app with seven real holes and judges
   each fix with live exploits: forty runs, forty patches, and a library upgrade that passes the build but stops the app.
   One added line, "start the app before you finish", got every agent to run it and ended the outages, but not the
   holes the ticket didn't name.

## What's on disk

```
moderne.ai/
├── README.md, 01..08-*.md     the course
└── lab/
    ├── lab1.sh                Lab 1 driver (Maven + OpenRewrite in Docker)
    ├── spring-petclinic/      Lab 1 target repo (reset with ./lab1.sh reset)
    ├── .m2/                   warm Maven cache (safe to delete; ~slow first run again)
    ├── cli/
        ├── Dockerfile         image `moderne-lab-cli`: Moderne CLI + JDK 8/11/17/21
        ├── repos.csv          the three Lab 2 repos
        ├── lab2.sh            opens a shell in the CLI container
        ├── lab2-smoke.sh      non-interactive replay of Lab 2 (how I verified it)
        ├── demo.sh            the slide demo, end to end (./demo.sh reset clears ws/demo)
        └── ws/                Lab 2 workspace (mounted at /ws in the container)
            ├── local/ai-found-cves/   Lab 4 demo repo (pins AI-found CVE versions)
            └── demo/                  slide demo output: clones, run1/run2.patch, logs/
    ├── lab4.sh                Lab 4 driver: scan / fix / jetty / reset
    ├── recipes/               Lab 5 recipe project (git; branch reference-solution = answer)
    ├── recipe-starter/        Moderne's official starter, for reading (needs a Code Genome token to build)
    └── rivals/
        ├── Dockerfile         image `moderne-lab-rivals`: modernize + atx + gh + JDKs
        ├── lab6.sh            opens a shell in it
        ├── score.sh           side-by-side scorecard (--test runs the test suites)
        └── ws/petclinic-{openrewrite,copilot,aws}/   identical Boot 2.7 starting points
    └── own/
        ├── Dockerfile         image `moderne-lab-own`: the CLI image + Python 3
        ├── own.sh             opens a shell in it, capped at 1.5 CPUs
        └── ws/                your repos (dns-mcp, dnsjava)
    ├── ab/                    Lab 8: ab.sh, Dockerfile.agent (image `moderne-lab-agent`: Copilot CLI + JDK 21), rewrite.yml,
    │                          ws/ (five petclinic clones), results/ (patches, transcripts, costs, logs)
    ├── ab2/                   Lab 8b: ab2.sh, ledger/ (the toy app), probe/ (exploit probe), rewrite.yml, results/
    ├── board/                 drift board: make_board_data.py → lab8-runs.csv, lab8b-runs.csv (+ lab8b-start-runs.csv), index.html
    └── uninstall.sh           removes what the labs created, nothing else (--dry-run first)
```

Nothing is installed on the host; the CLI's home (recipes, Maven/Gradle caches) lives in the Docker volume `moderne-lab-home`.
Every lab container is labelled `course=moderne-lab`. Cleanup when done, which lists everything before it deletes anything:

```bash
~/projects/general_chat/moderne.ai/lab/uninstall.sh --dry-run
```

`--all` also removes the cloned target repos and the results. Tools you already had (Docker, Maven, VS Code) are never touched.
The older one-liner, for the Lab 1–7 images only:

```bash
docker image rm moderne-lab-own moderne-lab-cli moderne-lab-rivals maven:3.9-eclipse-temurin-17 maven:3.9-eclipse-temurin-21 && docker volume rm moderne-lab-home moderne-lab-rivals-home
```

```bash
rm -rf ~/projects/general_chat/moderne.ai/lab
```

Re-verified 2026-10-27 (images rebuilt after a disk cleanup): Moderne CLI 4.11.1, `modernize` 1.0.77, `atx` 3.20.1.
2026-10-28: CLI self-updated to 4.12.0; Lab 2's run/study steps re-checked on it; Lab 7 added and run on it;
slide demo added, run by hand and then by `demo.sh`, with matching results.
Disk: the four images are about 9 GB; rebuilding also leaves build cache, which `docker builder prune -f` clears.
Researched and built 2026-10-08 against Moderne CLI 4.9.1, rewrite-maven-plugin 6.46.1,
rewrite-spring 6.37.1. This product moves fast. If a command fails, check
[docs.moderne.io](https://docs.moderne.io/) first.
