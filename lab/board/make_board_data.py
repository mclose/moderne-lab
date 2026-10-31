#!/usr/bin/env python3
"""Build the drift board's data files from the Lab 8 and Lab 8b results.

    .venv-free: plain python3 -I board/make_board_data.py [--dry-run]

Reads lab/ab/results and lab/ab2/results (never writes there) and writes
board/lab8-runs.csv, board/lab8b-runs.csv and, once
the start-the-app variant has run, board/lab8b-start-runs.csv. --dry-run prints the rows instead.
Every value comes from a result file; a value that is missing stays empty.
"""
import csv
import hashlib
import json
import pathlib
import re
import sys

LAB = pathlib.Path(__file__).resolve().parent.parent
AB, AB2, OUT = LAB / "ab" / "results", LAB / "ab2" / "results", LAB / "board"
RUN_NAME = re.compile(r"^A-(?:(?P<model>[a-z0-9.-]+)-)?clone(?P<n>[1-5])$")
DEFAULT_MODEL = "claude-sonnet-5.5"  # untagged runs are the brief's main run on the plan default

# Lab 8 fixes, by the patch's sha256 prefix. The recipe's patch differs from gemini clone1's only in the
# hunk header (the CLI writes the recipe name there), so both are labelled the same fix.
LAB8_FIX = {
    "aad67a": "Remove the dependency",
    "a9ae4c": "Drop the version (Boot picks 2.25.3)",
    "d81fd5": "Bump to 2.17.2",
    "a9fc34": "Bump to 2.26.1",
    "14f7b7": "Bump to 2.26.1",
    "6c3163": "Use ${log4j2.version}, add log4j-api",
    "638d7d": "Drop the version, add a comment",
}
PROBES = ["xxe-dom", "xxe-stax", "xxe-sax", "text4shell", "zipslip", "sqli-search", "sqli-overdrawn"]


def read(p: pathlib.Path) -> str:
    return p.read_text(errors="replace") if p.exists() else ""


def sha6(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:6]


def credits(p: pathlib.Path) -> str:
    m = re.search(r"^ai_credits (\S+)", read(p), re.M)
    return m.group(1) if m else ""


def seconds(p: pathlib.Path) -> str:
    return read(p).strip().rstrip("s")


def files_in(p: pathlib.Path) -> str:
    """Number of files a patch changes; empty if the patch file doesn't exist (not run or failed)."""
    return str(len(re.findall(r"^diff --git", read(p), re.M))) if p.exists() else ""


def runs(results: pathlib.Path):
    for p in sorted(results.glob("A-*.patch")):
        m = RUN_NAME.match(p.stem)
        if not m:
            raise SystemExit(f"unexpected result name: {p.name}")
        yield p.stem, m.group("model") or DEFAULT_MODEL, int(m.group("n")), p


def core_version(csv_path: pathlib.Path) -> str:
    """log4j-core version resolved in customers-service, from the DependencyInsight table; 'none' if absent."""
    if not csv_path.exists():
        return ""
    vs = {r[7] for r in csv.reader(l for l in csv_path.open() if not l.startswith("#"))
          if len(r) > 7 and "customers-service" in r[3] and r[6] == "log4j-core"}
    return ",".join(sorted(vs)) or "none"


def lab8():
    rows = []
    for name, model, n, p in runs(AB):
        key = sha6(p)
        rows.append({"run": name, "model": model, "clone": n, "fix": LAB8_FIX.get(key, "unlabelled"),
                     "patch": key, "log4j_core": core_version(AB / f"insight-{name}.csv"),
                     "build": read(AB / f"{name}.verify").strip(), "credits": credits(AB / f"{name}.cost"),
                     "seconds": seconds(AB / f"{name}.seconds"),
                     "recipe_still_changes": files_in(AB / f"X-{name[2:]}.patch")})
    for n in range(1, 6):
        p = AB / f"B-clone{n}.patch"
        rows.append({"run": f"B-clone{n}", "model": "recipe", "clone": n, "fix": LAB8_FIX.get(sha6(p), "unlabelled"),
                     "patch": sha6(p), "log4j_core": core_version(AB / "insight-B-clone1.csv"),
                     "build": read(AB / "B-clone1.verify").strip(), "credits": "0", "seconds": "",
                     "recipe_still_changes": "0" if "empty" in read(AB / "B-rerun.txt") else ""})
    return rows


def probe(name: str, path: pathlib.Path | None = None) -> dict:
    """Verdict per probe id. If the app didn't start, every probe is NOT RUN and startup is BROKEN."""
    got = {}
    for line in read(path or AB2 / f"{name}.probe.jsonl").splitlines():
        if line.strip():
            e = json.loads(line)
            got[e["id"]] = e["verdict"]
    if not got:
        return {"startup": "", **{k: "" for k in PROBES}}
    if "startup" in got:
        return {"startup": "BROKEN", **{k: "NOT RUN" for k in PROBES}}
    return {"startup": "OK", **{k: got.get(k, "") for k in PROBES}}


def versions(patch: pathlib.Path) -> tuple[str, str]:
    """commons-configuration2 and commons-text versions a patch sets ('' if it doesn't set one)."""
    t = re.sub(r"^\+\s*<!--.*$", "+", read(patch), flags=re.M)  # a version named in an XML comment is not a choice
    cfg = sorted(set(re.findall(r"^\+.*commons-configuration2(?:\.version)?>?\s*<?.*?(2\.\d+\.\d+)", t, re.M)))
    txt = sorted(set(re.findall(r"^\+.*commons-text\.version>(1\.\d+(?:\.\d+)?)<", t, re.M)
                     + re.findall(r"^\+\s*<version>(1\.1\d\.\d+)</version>", t, re.M)))
    def gone(lib: str) -> bool:  # the patch deletes the dependency and adds nothing back
        return bool(re.search(rf"^-.*<artifactId>{lib}<", t, re.M)) and not re.search(rf"^\+.*{lib}", t, re.M)
    return ",".join(cfg) or ("removed" if gone("commons-configuration2") else ""), \
        ",".join(txt) or ("removed" if gone("commons-text") else "")


def ran_jar(name: str) -> str:
    """Did the agent itself run the app? From its shared transcript, either signal counts: a shell command that runs
    the jar (some agents send its output to a file), or Spring Boot's startup line for the app (some wrap the command,
    e.g. in timeout). Unit tests only print "Started LedgerApplicationTest", so neither comes from the build."""
    t = read(AB2 / f"{name}.session.md")
    if not t:
        return ""
    ran = re.search(r"^\$ .*\bjava\b.*-jar\b", t, re.M) or re.search(r"Started LedgerApplication in ", t)
    return "yes" if ran else "no"


def lab8b_start():
    """VARIANT=start runs: the same ticket plus one line asking the agent to start the app."""
    rows = []
    for name, model, n, p in runs(AB2):
        if not model.startswith("start-"):
            continue
        cfg, txt = versions(p)
        rows.append({"run": name, "model": model.removeprefix("start-"), "clone": n, "patch": sha6(p),
                     "files": files_in(p), "build": read(AB2 / f"{name}.verify").strip(),
                     "credits": credits(AB2 / f"{name}.cost"), "seconds": seconds(AB2 / f"{name}.seconds"),
                     "cfg2": cfg, "text": txt, "agent_ran_jar": ran_jar(name), **probe(name)})
    return rows


def lab8b():
    rows = []
    base = probe("baseline")
    rows.append({"run": "baseline", "model": "baseline", "clone": "", "patch": "", "files": "0",
                 "build": read(AB2 / "baseline.verify").strip(), "credits": "0", "seconds": "",
                 "cfg2": "2.7", "text": "1.9", **base, "recipe_still_changes": "", "agent_ran_jar": ""})
    for name, model, n, p in runs(AB2):
        if model.startswith("start-"):  # the start-the-app variant has its own file
            continue
        cfg, txt = versions(p)
        rows.append({"run": name, "model": model, "clone": n, "patch": sha6(p), "files": files_in(p),
                     "build": read(AB2 / f"{name}.verify").strip(), "credits": credits(AB2 / f"{name}.cost"),
                     "seconds": seconds(AB2 / f"{name}.seconds"), "cfg2": cfg, "text": txt, **probe(name),
                     "recipe_still_changes": files_in(AB2 / f"X-{name[2:]}.patch"), "agent_ran_jar": ran_jar(name)})
    bp = AB2 / "B-clone1.patch"
    cfg, txt = versions(bp)
    for n in range(1, 6):
        rows.append({"run": f"B-clone{n}", "model": "recipe", "clone": n, "patch": sha6(AB2 / f"B-clone{n}.patch"),
                     "files": files_in(AB2 / f"B-clone{n}.patch"), "build": read(AB2 / "B-clone1.verify").strip(),
                     "credits": "0", "seconds": "", "cfg2": cfg, "text": txt, **probe("B-clone1"),
                     "recipe_still_changes": "", "agent_ran_jar": ""})
    # Trial build from the harness's first run: the recipe's code fixes and commons-text upgrade, with
    # commons-configuration2 left at 2.7 so the app starts. Shows which holes the recipe's code fixes reach.
    rows.append({"run": "B-trial-cfg2-2.7", "model": "recipe, config2 held at 2.7 (trial)", "clone": "",
                 "patch": "", "files": "", "build": "PASS", "credits": "0", "seconds": "", "cfg2": "2.7",
                 "text": "1.15.0", **probe("", LAB / "ab2" / "trial" / "probe-validation.jsonl"),
                 "recipe_still_changes": "", "agent_ran_jar": ""})
    return rows


def write(name: str, rows: list[dict], dry: bool):
    if dry:
        print(f"== would write board/{name} ({len(rows)} rows)")
        w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)
        return
    with (OUT / name).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)
    print(f"wrote board/{name} ({len(rows)} rows)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args not in ([], ["--dry-run"]):
        raise SystemExit("usage: make_board_data.py [--dry-run]")
    dry = args == ["--dry-run"]
    write("lab8-runs.csv", lab8(), dry)
    write("lab8b-runs.csv", lab8b(), dry)
    if start := lab8b_start():
        write("lab8b-start-runs.csv", start, dry)
