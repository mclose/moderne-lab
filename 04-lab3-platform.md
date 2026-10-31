# Lab 3: The Platform in a browser (optional, needs a GitHub login)

**Goal:** see the paid UI (marketplace, multi-repo dry run, results, data tables,
commit options) running against open-source repos on Moderne's public tenant.

**Needs:** a browser and a GitHub account. **You** do this one; I can't log in for you.

> **Permissions heads-up.** Signing in with GitHub asks for read/write on repo contents
> and pull requests ([their list](https://docs.moderne.io/administrator-documentation/moderne-platform/references/github-permissions)),
> because the Platform can commit and open PRs on your behalf. If you don't want to grant
> that to your main GitHub identity, use a throwaway GitHub account, or just do the
> dry-run part and stop before any commit dialog. Nothing here needs you to commit.

## Step 1: Sign in

Go to <https://app.moderne.io> and sign in with GitHub.

## Step 2: Pick an organization

Top-left **Organization** selector. Defaults to `Default` (a big pile of OSS repos).
Better for this lab: **Open Source → Sample Estate → Java Estate → Legacy Java Apps**
(5 repos: JavaVulnerableLab, SeleniumTDD, rrd4j, spring-petclinic, maxwell). That's the
same set Lab 2 uses, so you can compare.

## Step 3: Run a recipe across all of them

1. **Marketplace** → search `common static` → open **Common static analysis issues**.
2. Click **Dry run**.
3. Watch the activity view. The LSTs are *already built* (the platform rebuilds them
   continuously), so this skips the `mod build` step entirely. **That pre-built LST store
   is a big part of what you'd be paying for.**

## Step 4: Read the results

- Per-repo results list → click a file → click the **change reason** label next to it to see
  which sub-recipe made the change.
- **Data tables** tab: the same tables `mod study` exports in Lab 2, but in the UI.
- Try one search/analysis recipe too, e.g. search the marketplace for
  `Find and fix vulnerable dependencies` or `Dependency insight`, dry run it, and look at
  its data table and any **visualization** it offers.

## Step 5: Look at (don't click) the commit options

Select a couple of repos → **Commit selected results** → read the strategy options
(direct commit, branch, fork + PR, ...) → **Cancel**.
Their own docs say don't open PRs against projects that aren't yours.

## Step 6 (if visible): Moddy

If there's a **Moddy** button in the sidebar, try *"Which of these repos still use javax.persistence?"*
It's a restricted beta, so it may not appear for a public account. If it's not there, that's expected.

**Checkpoint:** you've now seen the same engine three ways: plugin (one repo), CLI (your
machine, many repos), Platform (their infra, pre-built, with a UI and mass commit).
That's the whole product line.
