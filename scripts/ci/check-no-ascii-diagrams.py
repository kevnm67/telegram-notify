#!/usr/bin/env python3
"""Fail when markdown contains an ASCII diagram (use D2 + a rendered SVG instead).

Canonical copy: kevnm67/engineering-toolkit scripts/ci/check-no-ascii-diagrams.py
Consumers vendor this single file (the toolkit is private, so pre-commit cannot
fetch it remotely); resync it when the toolkit copy changes.

Flags, in *.md / *.markdown / *.mdx:
  1. Box-drawing characters (U+2500-U+257F) anywhere: tree and box art.
  2. Inside untagged / text / ascii fences: arrow diagrams (->, -->, =>, unicode
     arrows, vertical connectors), +---+ boxes, and |-- / `-- directory trees.

Escape hatch for a genuine non-diagram (e.g. a captured log line), on the line
before the fence/line or at the end of it:
    <!-- ascii-diagram-ok: reason -->

Scope: human-facing docs only, i.e. README*, anything under docs/, wiki/ or
documentation/. SKILL.md, agent, command and CLAUDE.md files are model input, so
they are out of scope. Use --all (for example in a *.wiki.git clone) to lint every
markdown file regardless of path.

Usage: check-no-ascii-diagrams.py [--all] [FILE ...]
       (default files: every in-scope markdown file under cwd, skipping .git,
       node_modules, vendor and virtualenv directories)
Exit:  0 clean, 1 findings.
"""

# Vendored verbatim into consumer repos: exempt from each repo's ruff lint/format
# settings so the copy stays byte-identical to the toolkit canonical file.
# ruff: noqa
# fmt: off
import os
import re
import sys
from pathlib import Path

MD_SUFFIXES = {".md", ".markdown", ".mdx"}
SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__", ".terraform"}
BOX_RE = re.compile("[\u2500-\u257f]")
OK_RE = re.compile(r"<!--\s*ascii-diagram-ok\b")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})\s*([\w+-]*)")
DIAGRAM_LANGS = {"", "text", "txt", "ascii", "plain", "plaintext", "diagram"}
ARROW_RE = re.compile(r"-+>|<-+|=+>|<=+|[\u2190-\u21ff\u25b6\u25bc\u25b2\u25c0]")
VERTICAL_RE = re.compile(r"^\s*[|vV^]\s*$")
BOX_ASCII_RE = re.compile(r"^\s*\+-{2,}\+?|\+-{2,}\+\s*$|^\s*\|.*\|\s*$")
TREE_RE = re.compile(r"^\s*([|`]-{2}\s|\|\s{2,}[|`]-{2})")
BOX_MSG = "box-drawing characters (ASCII tree/diagram)"


DOC_DIRS = {"docs", "wiki", "documentation"}


def in_scope(path):
    parts = Path(os.path.normpath(path)).parts
    return Path(path).name.upper().startswith("README") or any(p in DOC_DIRS for p in parts[:-1])


def markdown_files(everything):
    found = []
    for root, dirs, names in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            path = os.path.normpath(os.path.join(root, name))
            if Path(name).suffix.lower() in MD_SUFFIXES and (everything or in_scope(path)):
                found.append(path)
    return sorted(found)


def is_diagram_line(line):
    return bool(
        ARROW_RE.search(line)
        or VERTICAL_RE.match(line)
        or TREE_RE.match(line)
        or (BOX_ASCII_RE.match(line) and len(line.strip()) > 6)
    )


def fence_diagram_line(body, start_line):
    """First line number of an ASCII diagram in a fence body, else None."""
    content = [(i, ln) for i, ln in enumerate(body, start_line) if ln.strip()]
    if len(content) < 2:
        return None
    return next((i for i, ln in content if is_diagram_line(ln)), None)


class Fence:
    def __init__(self, marker, lang, first_line, suppressed):
        self.marker = marker
        self.lang = lang
        self.first_line = first_line
        self.suppressed = suppressed
        self.body = []

    def closes_on(self, match):
        return bool(match) and match.group(1)[0] == self.marker and not match.group(2)

    def finding(self):
        if self.lang not in DIAGRAM_LANGS or self.suppressed:
            return None
        hit = fence_diagram_line(self.body, self.first_line)
        return (hit, "ASCII diagram in code fence") if hit else None


def scan_line(n, line, fence, prev_ok, findings):
    """Process one line; return the fence state to carry to the next line."""
    inline_ok = bool(OK_RE.search(line))
    suppressed = prev_ok or inline_ok or bool(fence and fence.suppressed)
    if BOX_RE.search(line) and not suppressed:
        findings.append((n, BOX_MSG))
    match = FENCE_RE.match(line)
    if fence is None:
        if match:
            return Fence(match.group(1)[0], match.group(2).lower(), n + 1, prev_ok or inline_ok)
        return None
    if fence.closes_on(match):
        found = fence.finding()
        if found:
            findings.append(found)
        return None
    fence.body.append(line)
    return fence


def check_file(path):
    findings = []
    fence = None
    prev_ok = False
    for n, line in enumerate(Path(path).read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        fence = scan_line(n, line, fence, prev_ok, findings)
        prev_ok = bool(OK_RE.search(line))
    return findings


def collapse(findings):
    """Keep one report per run of consecutive box-drawing lines."""
    kept, last = [], None
    for n, msg in sorted(set(findings)):
        if msg == BOX_MSG and last and last[1] == msg and n == last[0] + 1:
            last = (n, msg)
            continue
        kept.append((n, msg))
        last = (n, msg)
    return kept


def main(argv):
    everything = "--all" in argv
    names = [a for a in argv if a != "--all"]
    if names:
        files = names if everything else [f for f in names if in_scope(f)]
    else:
        files = markdown_files(everything)
    total = 0
    for path in files:
        if not Path(path).is_file():
            continue
        for n, msg in collapse(check_file(path)):
            print(f"{path}:{n}: {msg}")
            total += 1
    if total:
        print(
            "\nASCII diagrams are not allowed. Author a D2 diagram "
            "(docs/architecture/*.d2), render the SVG, and embed it. "
            "False positive? add <!-- ascii-diagram-ok: reason --> before it.",
            file=sys.stderr,
        )
        return 1
    print(f"OK: no ASCII diagrams in {len(files)} markdown file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
