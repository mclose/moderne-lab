# Part 1: The pitch (what you'd be buying)

Read-only. No setup. You decide when you've got it.

## 1.1 The one idea everything rests on

**OpenRewrite** (open source, Apache 2.0) changes code by running **recipes** against a
**Lossless Semantic Tree (LST)**. An LST is the code parsed *with full type information*
(it knows `List` is `java.util.List`, which version of Spring is on the classpath, etc.)
and *lossless* (formatting and comments survive, so diffs look like a human wrote them).

That's the difference from regex/sed and from "ask an LLM to edit the file":

| Approach            | Knows types? | Same result every run? | Scales to 5,000 repos? |
|---------------------|--------------|------------------------|------------------------|
| sed / regex         | no           | yes                    | yes, but breaks things |
| LLM coding agent    | sort of      | no                     | expensive, needs review of every diff |
| OpenRewrite recipe  | yes          | yes                    | yes, *if* you have LSTs for all 5,000 |

A recipe is either imperative Java (a visitor over the tree) or declarative YAML that
composes other recipes. `UpgradeSpringBoot_3_5`, which you'll run in Lab 1, is a
composite of hundreds of smaller recipes (javax→jakarta, property renames, dependency
bumps, Java 17 upgrade, ...).

**The catch Moderne sells against:** building an LST means *compiling the project*
(resolving dependencies, the right JDK, the build tool). Doing that for one repo is just
`mvn rewrite:run`. Doing it for 10,000 repos, every night, with the right JDK for each,
is the hard part, and it's what Moderne actually charges for.

## 1.2 Product map (as of Oct 2026)

Moderne repositioned in 2026 as "the deterministic layer for AI coding agents." Same
engine, new framing: agents decide *what* to do; recipes do the change reliably.

| Product | What it is | Free? |
|---|---|---|
| **OpenRewrite** | The OSS engine + thousands of OSS recipes. Maven/Gradle plugin. One repo at a time. | Yes (Apache 2.0) |
| **Moderne CLI** (`mod`) | Clone/build/run recipes across *many* repos locally; stores LSTs; `mod study` turns results into spreadsheets; `mod git` commits/branches across all repos; `mod search` (Trigrep). | Public repos: yes (sign-in/token for some features). Private repos: license. |
| **Moderne Platform** (SaaS, app.moderne.io) | Pre-built LSTs for your whole estate, recipe marketplace (7k+), dry-run across orgs, data tables, visualizations, DevCenter dashboards, mass commit/PR. | Public tenant usable with GitHub login on OSS repos. Your code = contract. |
| **Moderne DX** | The same thing, on-prem / air-gapped (CLI + IDE + reporting). | Contract only. |
| **Moddy** | Natural-language agent inside the Platform that finds and runs recipes ("help me upgrade to Spring Boot 3.5"). Restricted beta. | Contract. |
| **Agent tools**: MCP server, Prethink, Trigrep, agent chat | Feed Claude/Copilot/etc. with LST-derived context. *Prethink* writes architecture/endpoint/test-gap context into `.moderne/context/` and `CLAUDE.md`. *Trigrep* = trigram + LST-semantic code search (`implements:Repository`). `mod claude chat` / `mod copilot chat` drive an agent over a repo set. | Varies; mostly needs a tenant. |
| **Proprietary recipes** (Moderne Source Available License) | The harder recipes, e.g. multi-repo impact analysis and some security fixes. | Customers only. |
| **Backpatch Alliance** | Patched builds of old library versions you can't upgrade off (think extended support for OSS deps). | $2k/mo and up |
| **Code Genome Project** | Where recipes and the CLI are published now (moved off Maven Central for rate limits). OSS recipes still land on Central too. | Authenticated users; proprietary recipes need entitlement |

## 1.3 What it costs (their published "typical" numbers)

From moderne.ai/pricing. These are "contact sales" anchors, not a rate card:

- **Commercial:** ~$250K. Up to ~1,000 devs, hundreds of repos, hybrid SaaS, a part-time forward-deployed engineer.
- **Enterprise:** ~$2M. Thousands of devs, hundreds of millions of LOC, can include DX on-prem.
- **Fully Managed Service:** ~$5M. Moderne owns the outcome ("your estate is on Java 21 by Q3").

Takeaway: this is an **estate-scale** purchase. Below a few hundred repos, OpenRewrite
plus a CI job usually covers it. The buy case is *many repos × recurring migrations ×
proof for auditors that it happened everywhere*.

## 1.4 Where it fits vs. alternatives

- **Dependabot / Renovate:** bump version numbers. They don't rewrite the code that breaks when you bump.
- **Sourcegraph Batch Changes:** multi-repo change orchestration, but the change itself is usually a script/regex you write.
- **GitHub Copilot app modernization / Amazon Q Developer transform:** LLM-driven Java upgrades. Microsoft's Java upgrade tooling uses OpenRewrite recipes for the deterministic parts (worth checking how Amazon's does it if that's your comparison). Moderne's pitch: "same engine, but across the whole estate and repeatable."
- **Plain LLM agents (Claude Code, etc.):** great per repo, nondeterministic, review cost scales linearly. Moderne wants to be the tool your agent calls.

## 1.5 Questions you'd ask on a sales call

1. How are LSTs built for repos with weird builds (Bazel, custom Gradle, private artifact repos)? What % of a typical estate builds on first try?
2. What runs in our network vs. theirs? (The "hybrid SaaS" answer: an agent/connector in your network builds LSTs; the SaaS stores them.)
3. Which recipes we'd need are proprietary vs. OSS? Can we write our own and run them on the Platform?
4. How are results committed: direct push, PR per repo, fork? How does that interact with branch protection and CODEOWNERS?
5. What does Moddy/Prethink send to which LLM? Can we bring our own model?
6. What is the forward-deployed engineer actually doing for us in year one?

## 1.6 Optional reading (skim, don't study)

- [OpenRewrite: What is a recipe?](https://docs.openrewrite.org/concepts-and-explanations/recipes)
- [OpenRewrite: Lossless Semantic Trees](https://docs.openrewrite.org/concepts-and-explanations/lossless-semantic-trees)
- [Moderne docs home](https://docs.moderne.io/) (product nav is the best map)
- [Moderne pricing](https://www.moderne.ai/pricing)
- [Trigrep](https://docs.moderne.io/user-documentation/agent-tools/trigrep), [Prethink](https://docs.moderne.io/user-documentation/agent-tools/prethink), [Moddy](https://docs.moderne.io/user-documentation/moddy/moddy-platform)

**Checkpoint:** can you explain to someone why "it has to compile the code first" is both
the product's strength and the thing you pay for? Then go to Lab 1.
