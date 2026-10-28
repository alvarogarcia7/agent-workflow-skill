#!/usr/bin/env python3
"""Resolve git conflict markers in append-only files (decision logs, changelogs) by keeping BOTH sides.

Usage: keep-both.py <file> [<file> ...]   (then `git add` the file and continue the rebase/merge)

* Works with merge.conflictStyle=merge, diff3 and zdiff3 (the common-ancestor section is dropped).
* Puts a blank line between the two sides so entries do not run together.
* Reports duplicate decision ids (lines starting with **D-nn) after merging: two agents may have used the same number.
* Exit status: 1 if conflict markers remain in any file (or a file cannot be read), else 0.
"""
import collections
import re
import sys

PATTERN = re.compile(
    r"<<<<<<< [^\n]*\n(.*?)(?:\|\|\|\|\|\|\| [^\n]*\n.*?)?=======\n(.*?)>>>>>>> [^\n]*\n", re.S
)
MARKERS = re.compile(r"^(<<<<<<< |=======$|>>>>>>> )", re.M)
DECISION_ID = re.compile(r"^\*\*(D-\d+)\b", re.M)


def join(ours, theirs):
    if not ours.strip():
        return theirs
    if not theirs.strip():
        return ours
    return ours.rstrip("\n") + "\n\n" + theirs


def main(paths):
    status = 0
    for path in paths:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print(f"{path}: {e}", file=sys.stderr)
            status = 1
            continue
        fixed = PATTERN.sub(lambda m: join(m.group(1), m.group(2)), text)
        if fixed != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(fixed)
        left = len(MARKERS.findall(fixed))
        print(f"{path}: remaining markers: {left}")
        if left:
            status = 1
        counts = collections.Counter(DECISION_ID.findall(fixed))
        for did, n in sorted(counts.items()):
            if n > 1:
                print(f"{path}: WARNING duplicate decision id {did} ({n} entries): renumber one", file=sys.stderr)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
