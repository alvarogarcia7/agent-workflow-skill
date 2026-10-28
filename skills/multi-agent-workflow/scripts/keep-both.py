#!/usr/bin/env python3
"""Resolve git conflict markers in append-only files (decision logs, changelogs) by keeping BOTH sides.
Usage: keep-both.py <file> [<file> ...]   (then `git add` the file and continue the rebase/merge)."""
import re
import sys

PATTERN = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    fixed = PATTERN.sub(lambda m: m.group(1) + m.group(2), text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(fixed)
    left = len(re.findall(r"^(<<<<<<<|=======|>>>>>>>)", fixed, re.M))
    print(f"{path}: remaining markers: {left}")
