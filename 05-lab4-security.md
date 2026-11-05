# Lab 4: Security view: AI-found CVEs vs. a deterministic fixer

**Goal:** see what Moderne/OpenRewrite actually does for security, using vulnerabilities
that AI found in 2026, and see where it falls short.

**Spoiler, and the point of the lab:** Moderne is a **remediation** engine, not a scanner. It
fixes what its advisory data knows about, everywhere, the same way every time. The newest
AI-found bug in this lab isn't in that data yet, so it sails through. You close that gap
yourself with a 7-line recipe.

**Needs:** Docker. No accounts.

---

## 4.1 Context (read, ~1 page)

**2026 is the year AI started finding CVEs at scale.**

- **Project Glasswing (Anthropic, announced 2026-04-07).** Built on *Claude Mythos Preview*, a
  model Anthropic isn't releasing generally. Access goes to defenders instead: launch partners
  (AWS, Apple, Google, Microsoft, the Linux Foundation, ...) and 40+ infrastructure orgs, plus
  $100M in usage credits. Anthropic publishes a disclosure ledger at
  [red.anthropic.com/2026/cvd](https://red.anthropic.com/2026/cvd/): thousands of findings
  committed, a few hundred publicly revealed so far, mostly C/C++ (FFmpeg, wolfSSL, FreeRDP, ...).
- **OpenAI:** *Aardvark* (Oct 2025) became **Codex Security** (research preview, 2026-03-06).
  Credited finds include GnuTLS and Gogs. I couldn't confirm which GPT-5.x/6 model is behind it.
- **Google:** Big Sleep / CodeMender (SQLite CVE-2025-6965 is the famous one).

**What that means operationally:** the discovery rate goes up and the disclosure-to-exploit window
shrinks. The bottleneck moves from *finding* to *fixing everywhere*. That is Moderne's pitch:
deterministic, estate-wide remediation, with AI agents deciding *what* to fix and recipes doing it.

**The Java CVEs in this lab:**

| CVE | Library | AI angle | Fixed |
|---|---|---|---|
| **CVE-2026-19204** | Jetty WebSocket core | **Found by Claude Mythos Preview**. GHSA-85fq-fc5f-7j7g: "discovered by Claude, Anthropic's AI assistant", triaged by Ada Logics. A reserved-opcode frame skips the max-frame-size check; ~15 bytes makes the server allocate ~2 GiB and run out of memory. High. Published 2026-09-16. | 12.1.12 / 12.0.38 |
| **CVE-2026-34197** | ActiveMQ broker | Jolokia RCE, CVSS 8.8, **on CISA's Known Exploited list**. Human-credited (Horizon3.ai), but the researcher described the find as "80% Claude". | 6.2.3 / 5.19.5 |
| **CVE-2026-28208** | junrar | Path traversal → arbitrary file write. Human-credited (Feb 2026); **Mythos independently rediscovered it** in May. | 7.5.8 |

Sources: [Anthropic finding ANT-2026-Y9CTVKPP](https://red.anthropic.com/2026/cvd/findings/ANT-2026-Y9CTVKPP.html),
[Jetty GHSA](https://github.com/jetty/jetty.project/security/advisories/GHSA-85fq-fc5f-7j7g),
[ActiveMQ advisory](https://activemq.apache.org/security-advisories.data/CVE-2026-34197-announcement.txt),
[Help Net Security on "80% Claude"](https://www.helpnetsecurity.com/2026/04/09/apache-activemq-rce-vulnerability-cve-2026-34197-claude/),
[junrar GHSA](https://github.com/advisories/GHSA-j273-m5qq-6825),
[Anthropic ANT-2026-9VJ9JJXQ](https://red.anthropic.com/2026/cvd/findings/ANT-2026-9VJ9JJXQ.html).

> FYI: none of the three 2026 CVEs Lab 2 flagged in petclinic (log4j-api, jackson-databind 3.x,
> pgjdbc) are AI-credited. All three credit human reporters.

---

## 4.2 Hands-on: dependency CVEs (the scanner's view)

The demo repo `lab/cli/ws/local/ai-found-cves` is a tiny Maven project I made that pins
vulnerable versions of all three libraries (plus Jetty 11, the same CVE on an older line):

```bash
cat ~/moderne-lab/lab/cli/ws/local/ai-found-cves/pom.xml
```

**First, the paywall (optional, 1 min).** In the Lab 2 container (`lab/cli/lab2.sh`), try:

```
mod build ./local/ai-found-cves
mod run ./local/ai-found-cves --recipe org.openrewrite.java.dependencies.DependencyVulnerabilityCheck
```

> `A valid license is required: this repository is not an open source repository.`

The build works, but the run refuses: the CLI checks whether the repo is public. **Your private code
is the product.** So we use the free OpenRewrite Maven plugin instead (same recipe, one repo):

```bash
cd ~/moderne-lab/lab
```

```bash
./lab4.sh scan
```

What you should see (I got exactly this):

- **22 rows.** ActiveMQ 6.2.2 has 8 CVEs including **CVE-2026-34197**. junrar has
  **CVE-2026-28208** and a later one. Note the `depth` column: depth 1–2 are *transitive* (jackson
  pulled in by ActiveMQ). Nobody declared those, which is why you need a tool for this.
- **A patch:** ActiveMQ 6.2.2 → 6.2.6, junrar 7.5.7 → 7.5.10. It fixes the transitive jackson
  CVEs by bumping the parent, not by pinning jackson. Minimal blast radius.
- **No Jetty.** Neither Jetty line shows up. **The one bug in this repo that Claude actually found is invisible.**

### Why the scanner missed CVE-2026-19204

Work it out, then check:

1. The recipe's vulnerability data is a snapshot of the GitHub Advisory Database **baked into the recipe
   JAR** at build time. The last `rewrite-java-security` on Maven Central is **3.38.1, built
   2026-08-17**. The Jetty advisory went public **2026-09-16**. Newer recipe releases go to the
   Code Genome Project (Moderne's repo), so a free user on Central is stuck with stale data.
2. Even with fresh data: the advisory lists `org.eclipse.jetty.websocket:websocket-core-common`.
   That's Jetty **10/11's** artifact name. Jetty **12** ships as `jetty-websocket-core-common`. A
   coordinate-matching scanner can miss the 12.x line entirely. (Moderne's Platform data may correct
   this; I couldn't check without a license.)
3. It's a **repository** advisory on jetty/jetty.project. As of today it doesn't come back from the
   global reviewed-advisory API (`api.github.com/advisories/GHSA-85fq-fc5f-7j7g` returns nothing),
   which is where most scanners sync from.

**Lesson:** AI-speed discovery + batch-updated advisory data = a gap. *Days to weeks* where the
bug is public and your scanner still says you're clean.

### Apply the scanner's fix, then close the gap yourself

```bash
./lab4.sh fix
```

Now the recipe the scanner doesn't have. I wrote it as a 7-line declarative recipe in Lab 5's
project (`lab/recipes/src/main/resources/META-INF/rewrite/security.yml`):

```bash
cat recipes/src/main/resources/META-INF/rewrite/security.yml
```

```bash
./lab4.sh jetty
```

Jetty 12.1.11 → **12.1.14** (newest 12.1 patch). **Jetty 11.0.26 is left alone**, and that's correct:
the 11.x fix (11.0.32) only exists as a *commercial* Jetty release; Maven Central stops at 11.0.26.
No free patch exists. That's exactly the hole Moderne's **Backpatch Alliance** ($2k/month and up) sells into:
patched builds of old library lines you can't upgrade off.

At estate scale, that recipe is what you'd push to every repo the morning the advisory drops, without
waiting for the scanner vendor.

```bash
./lab4.sh reset
```

---

## 4.3 Hands-on: code-level fixes (and their limits)

Dependency bumps are the easy half. Can it fix *your* vulnerable code? Use JavaVulnerableLab (public,
so the CLI is fine). In the Lab 2 container:

```bash
~/moderne-lab/lab/cli/lab2.sh
```

Inside:

```
mod run ./repos/CSPF-Founder/JavaVulnerableLab --recipe org.openrewrite.java.security.FixSqlInjectionConcat
```

Look at the patch it printed (the path is in the output, ending in `fix.patch`). When I ran it: **3 files fixed**
(`LoginValidator`, `EmailCheck`, `UsernameCheck`). The textbook login injection became:

```java
PreparedStatement stmt = con.prepareStatement("select * from users where username=? and password=?");
stmt.setString(1, user);
stmt.setString(2, pass);
rs=stmt.executeQuery();
```

Correct, minimal, and identical every run. **Now the limits:**

```
grep -n 'executeUpdate("INSERT' repos/CSPF-Founder/JavaVulnerableLab/src/main/java/org/cysecurity/cspf/jvl/controller/Register.java
```

```
grep -rl executeQuery repos/CSPF-Founder/JavaVulnerableLab/src/main/webapp | wc -l
```

- `Register.java` has two string-concatenated INSERTs **it didn't touch** (the recipe only recognizes some shapes of concatenated SQL).
- **15 JSP files** run SQL. JSP isn't parsed as Java, so the recipe never sees them.

Try the broader composite too, which also patched XXE and XPath injection when I ran it:

```
mod run ./repos/CSPF-Founder/JavaVulnerableLab --recipe org.openrewrite.java.security.OwaspTopTen
```

`exit` the container when done.

## 4.4 Takeaways (the honest security view)

| | Moderne / OpenRewrite | AI agent (Mythos, Codex Security, Claude Code) |
|---|---|---|
| Finds new bugs | No. Only what's in advisory data or a recipe pattern | **Yes**, that's the 2026 story |
| Fix quality | Deterministic, reviewable, identical across 5,000 repos | Varies run to run; every diff needs review |
| Coverage | Only what the recipe matches (missed `Register.java`, JSPs) | Can reason about odd code, can also be wrong |
| Speed to new CVE | As fast as someone writes/ships the recipe | Immediate, but per repo |
| Where it fits | **Remediation at scale**, proof it happened everywhere | Discovery and the long tail |

The combination Moderne is selling: **AI decides, recipes execute**. The useful question for a
security team isn't "scanner or Moderne". It's "when an AI finds the next Jetty bug, how many hours until
all our repos are patched, and can we prove it?"

Optional: open Claude Code in `lab/cli/ws/repos/CSPF-Founder/JavaVulnerableLab` and ask it to fix the
`Register.java` injection the recipe missed. Compare its diff to the recipe's, then reset with
`git checkout -- .`.

**Checkpoint:** you can explain why "public on GitHub" ≠ "in my scanner", and where a deterministic fixer
helps vs. where you still need a human or an agent. → Lab 5 turns that Jetty recipe into a proper,
tested artifact and has Claude write the next one.
