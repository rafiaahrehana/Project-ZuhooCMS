"""Second pass: the warnings `flutter analyze` reports that pass one does not.

  5. unused_element        — a private declaration nothing references
  6. unused_local_variable — a local assigned and never read
  7. unnecessary_non_null_assertion / dead_null_aware_expression

Three traps this pass had to be taught, each of which produced a wave of
confident nonsense before it was:

  * `'$_base/thing'` — a use inside a string. Blanking string bodies (needed
    to find declarations) hides it, so uses are counted in source that keeps
    strings and drops only comments.
  * a top-level `final somethingProvider = ...` is used from other files, so
    counting uses within one file says nothing.
  * `existing?.isHeaderAccount ?? false` — the `?.` makes the expression
    nullable however non-nullable the field is, so the fallback is live.

Same discipline as pass one: skip anything ambiguous. A warning that is not
real is worse than none, because acting on it damages working code.
"""
import io
import os
import re
import sys

ROOTS = ['lib', 'test']


def blank(src, strings=True):
    """Blank comments, and optionally string bodies, preserving offsets."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(ch if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
            continue
        if c in '"\'':
            raw = i > 0 and src[i - 1] == 'r'
            triple = src[i:i + 3] in ('"""', "'''")
            q = src[i:i + 3] if triple else c
            j = i + len(q)
            while j < n:
                if not raw and src[j] == '\\':
                    j += 2
                    continue
                if src[j:j + len(q)] == q:
                    j += len(q)
                    break
                j += 1
            else:
                j = n
            chunk = src[i:j]
            out.append(''.join(ch if ch == '\n' else ' ' for ch in chunk)
                       if strings else chunk)
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


FILES = []
for root in ROOTS:
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.endswith('.dart'):
                FILES.append(os.path.join(dp, f).replace('\\', '/'))

RAW = {p: io.open(p, encoding='utf-8').read() for p in FILES}
CLEAN = {p: blank(RAW[p]) for p in FILES}          # for finding declarations
USES = {p: blank(RAW[p], strings=False) for p in FILES}   # for counting uses
ALL_USES = '\n'.join(USES.values())

FINDINGS = []


def report(path, pos, msg):
    FINDINGS.append((path, CLEAN[path].count('\n', 0, pos) + 1, msg))


def count(text, name):
    # `$` must NOT be excluded before the name: in `'$_base/x'` the dollar is
    # the interpolation marker, not part of the identifier, and treating it as
    # one hid every use a repository makes of its own path constant.
    return len(re.findall(r'(?<![A-Za-z0-9_])' + re.escape(name) +
                          r'(?![A-Za-z0-9_])', text))


# ── 5: a private declaration nothing references ──────────────────────

PRIVATE_DECL = [
    re.compile(r'^class\s+(_\w+)', re.M),
    re.compile(r'^(?:[\w<>?, \[\]$.]+\s+)?(_\w+)\s*\(', re.M),
    re.compile(r'^(?:final|const|var)\s+(_\w+)\s*=', re.M),
    re.compile(r'^  (?:static\s+)?(?:[\w<>?, \[\]$.]+\s+)?(_\w+)\s*\(', re.M),
    re.compile(r'^  (?:late\s+)?(?:final|const|var|static\s+\w+)\s+'
               r'[\w<>?, \[\]$.]*?\b(_\w+)\s*[;=]', re.M),
]

for path, text in CLEAN.items():
    names = set()
    for pat in PRIVATE_DECL:
        for m in pat.finditer(text):
            names.add(m.group(1))
    for name in sorted(names):
        if name.startswith('__'):
            continue
        # Uses counted in source that keeps strings — `'$_base/x'` is a use.
        if count(USES[path], name) <= 1:
            report(path, text.index(name), f'`{name}` is declared and never used')


# ── 6: a local assigned and never read ───────────────────────────────

LOCAL_RE = re.compile(
    r'^\s{4,}(?:final|var|const)\s+(?:[\w<>?, \[\]$.]+\s+)?(\w+)\s*=', re.M)

# Anything also declared at column zero is a top-level name, used from other
# files; counting its uses in one file proves nothing.
TOP_LEVEL = set()
for text in CLEAN.values():
    for m in re.finditer(r'^(?:final|const|var|late)\s+(?:[\w<>?, \[\]$.]+\s+)?(\w+)\s*=',
                         text, re.M):
        TOP_LEVEL.add(m.group(1))

for path, text in CLEAN.items():
    for m in LOCAL_RE.finditer(text):
        name = m.group(1)
        if name.startswith('_') or name in TOP_LEVEL:
            continue
        if count(USES[path], name) <= 1:
            report(path, m.start(), f'local `{name}` is assigned and never read')


# ── 7: null handling — REMOVED, it could not be made sound ──────────
#
# The idea was to flag `x.field!` and `x.field ?? y` where the field is
# declared non-nullable. It cannot work at field-name granularity, and all
# three findings it produced were wrong:
#
#   s.body!        — a record field `(title: String, body: String?)`, not the
#                    `final String body` some other class declares
#   row.totalDays  — a nullable `int? get totalDays`, while a different class
#                    has `final int totalDays`
#   file.path!     — an SDK type's nullable path, not `PickedAttachment.path`
#
# Getting it right needs the receiver's actual type, which means real type
# inference. A check that tells you to delete a live null-guard is worse than
# no check at all.


FINDINGS.sort()
seen = set()
for path, line, msg in FINDINGS:
    if (path, line, msg) in seen:
        continue
    seen.add((path, line, msg))
    print(f'{path}:{line}  {msg}')

print(f'\n{len(seen)} finding(s) across {len(FILES)} files')
sys.exit(1 if seen else 0)
