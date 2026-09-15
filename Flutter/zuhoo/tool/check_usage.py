"""A stand-in for `flutter analyze`, for a machine with no Dart SDK.

It cannot type-check. What it can do is use the repo's own class declarations
as ground truth and check every use of them against it. That catches the
error classes that actually bite when writing Dart without a compiler:

  1. a named argument a constructor does not declare
  2. a required named argument left out
  3. a static member (`Perms.foo`) a class does not declare
  4. an instance member (`x.foo`) a class does not declare, where the
     receiver's type is declared in the same file

Deliberately conservative: anything it cannot resolve with confidence is
skipped rather than guessed at. Every finding should be real.
"""
import io
import os
import re
import sys
from collections import defaultdict

ROOTS = ['lib', 'test']

# ── crude but adequate source cleaning ───────────────────────────────


def strip_noise(src):
    """Blank out comments and string bodies, preserving offsets and newlines."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        # line comment
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
            continue
        # block comment
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(ch if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
            continue
        # strings (incl. raw and triple)
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
            out.append(''.join(ch if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def files():
    for root in ROOTS:
        for dp, _, fs in os.walk(root):
            for f in fs:
                if f.endswith('.dart'):
                    yield os.path.join(dp, f).replace('\\', '/')


SRC = {}
CLEAN = {}
for p in files():
    SRC[p] = io.open(p, encoding='utf-8').read()
    CLEAN[p] = strip_noise(SRC[p])


def line_of(path, pos):
    return CLEAN[path].count('\n', 0, pos) + 1


# ── index every class declared in the repo ───────────────────────────

CLASS_RE = re.compile(
    r'^(?:abstract\s+)?(?:final\s+|base\s+|interface\s+|sealed\s+|mixin\s+)*'
    r'class\s+(\w+)', re.M)


def block_at(text, open_brace):
    """Return (start, end) of the {...} block starting at open_brace."""
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return open_brace, i
    return open_brace, len(text)


class ClassInfo:
    def __init__(self, name, path):
        self.name = name
        self.path = path
        self.supers = []
        self.instance = set()   # fields, getters, methods
        self.static = set()     # static consts/methods, factories, named ctors
        self.ctor_named = {}    # ctor name ('' = unnamed) -> {param: required}
        self.has_ctor = False
        self.body = (0, 0)   # where the class body sits in its own file


CLASSES = {}          # name -> [ClassInfo]  (a name can repeat across files)
BY_FILE = defaultdict(dict)   # path -> {name: ClassInfo}

MEMBER_PATTERNS = [
    # final Type name; / final name = / late final Type name
    re.compile(r'^\s*(?:late\s+)?(?:final|const|static\s+final|static\s+const)\s+'
               r'[\w<>?, \[\]$.]*?\b(\w+)\s*[;=]', re.M),
    # Type name; declarations without final
    re.compile(r'^\s{2,}(?:[A-Z][\w<>?, \[\]$.]*)\s+(\w+)\s*;', re.M),
    # getters
    re.compile(r'^\s*(?:static\s+)?[\w<>?, \[\]$.]+\s+get\s+(\w+)', re.M),
    # methods (incl. void / Future<...> / Type)
    re.compile(r'^  (?:static\s+)?(?:[\w<>?, \[\]$.]+\s+)(\w+)(?:<[^>]*>)?\s*\(', re.M),
    # factories
    re.compile(r'^\s*factory\s+\w+\.(\w+)', re.M),
]

STATIC_PATTERNS = [
    re.compile(r'^\s*static\s+(?:const|final)\s+(?:[\w<>?, \[\]$.]+\s+)?(\w+)\s*=', re.M),
    re.compile(r'^\s*static\s+(?:[\w<>?, \[\]$.]+\s+)?(\w+)\s*\(', re.M),
    re.compile(r'^\s*static\s+[\w<>?, \[\]$.]+\s+get\s+(\w+)', re.M),
    re.compile(r'^\s*factory\s+\w+\.(\w+)', re.M),
]


def parse_ctor_params(sig):
    """sig is the text inside the constructor's parentheses."""
    out = {}
    m = re.search(r'\{(.*)\}', sig, re.S)
    if not m:
        return out
    body = m.group(1)
    # split top-level commas
    parts, depth, cur = [], 0, ''
    for ch in body:
        if ch in '<([{':
            depth += 1
        elif ch in '>)]}':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    parts.append(cur)

    for part in parts:
        part = part.strip()
        if not part or part.startswith('super.key'):
            continue
        required = part.startswith('required ')
        part = re.sub(r'^required\s+', '', part)
        # drop a default value
        has_default = '=' in part
        part = part.split('=')[0].strip()
        mm = re.search(r'(?:this\.|super\.)?(\w+)\s*$', part)
        if mm:
            out[mm.group(1)] = required and not has_default
    return out


for path, text in CLEAN.items():
    for m in CLASS_RE.finditer(text):
        name = m.group(1)
        brace = text.find('{', m.end())
        if brace < 0:
            continue
        header = text[m.end():brace]
        start, end = block_at(text, brace)
        body = text[start:end]

        info = ClassInfo(name, path)
        for sm in re.finditer(r'\b(?:extends|with|implements)\s+([\w,\s<>]+)', header):
            for s in re.split(r'[,\s]+', sm.group(1)):
                if s and s[0].isupper():
                    info.supers.append(re.sub(r'<.*', '', s))

        for pat in MEMBER_PATTERNS:
            for mm in pat.finditer(body):
                info.instance.add(mm.group(1))
        for pat in STATIC_PATTERNS:
            for mm in pat.finditer(body):
                info.static.add(mm.group(1))

        # Constructors — declarations only.
        #
        # A call site inside the class (`copyWith` returning `Foo(...)`) matches
        # the same name-then-paren shape, and treating one as a declaration
        # overwrites the real signature with whatever that call happened to
        # pass. So a declaration must sit at class-body indentation and be
        # followed by `;`, `{`, `:` or `=>` once its parameter list closes.
        for cm in re.finditer(
                r'\n  (?:const |factory )?' + re.escape(name) +
                r'(?:\.(\w+))?\s*\(', body):
            cname = cm.group(1) or ''
            popen = body.index('(', cm.start())
            depth, k = 0, popen
            while k < len(body):
                if body[k] == '(':
                    depth += 1
                elif body[k] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            tail = body[k + 1:k + 40].lstrip()
            if tail[:1] not in (';', '{', ':') and not tail.startswith('=>'):
                continue
            info.ctor_named[cname] = parse_ctor_params(body[popen:k + 1])
            info.has_ctor = True
            if cname:
                info.static.add(cname)

        CLASSES.setdefault(name, []).append(info)
        info.body = (start, end)
        BY_FILE[path][name] = info

# resolve inherited members one level (enough for our own hierarchies)
for infos in CLASSES.values():
    for info in infos:
        for sup in info.supers:
            for si in CLASSES.get(sup, []):
                info.instance |= si.instance


def unique(name):
    """The single ClassInfo for a name, or None when ambiguous/unknown."""
    infos = CLASSES.get(name)
    if not infos or len(infos) > 1:
        return None
    return infos[0]


FINDINGS = []


def report(path, pos, msg):
    FINDINGS.append((path, line_of(path, pos), msg))


# ── 1 & 2: constructor arguments ─────────────────────────────────────

CALL_RE = re.compile(r'(?<![\w.$])([A-Z]\w+)(?:\.(\w+))?\s*\(')

for path, text in CLEAN.items():
    for m in CALL_RE.finditer(text):
        cname, ctor = m.group(1), m.group(2) or ''
        info = unique(cname)
        if info is None or not info.has_ctor:
            continue

        # A declaration is not a call. Skipping anything at the start of a line
        # was far too broad — it swallowed `    LoadingButton(...)` and every
        # other call written as its own statement, which is most of them, and
        # left both constructor checks silently dead.
        #
        # A declaration is specifically: this class, inside its own body, at
        # class-member indentation.
        if info.path == path and info.body[0] <= m.start() <= info.body[1]:
            line_start = text.rfind(chr(10), 0, m.start()) + 1
            if re.fullmatch(r'  (?:const |factory )?', text[line_start:m.start()]):
                continue
        # only check classes with no subclass overriding the ctor shape
        if ctor not in info.ctor_named:
            continue
        params = info.ctor_named[ctor]
        if not params:
            continue

        popen = m.end() - 1
        depth, k = 0, popen
        while k < len(text):
            if text[k] == '(':
                depth += 1
            elif text[k] == ')':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        args = text[popen + 1:k]

        # named args at depth 1 only
        given, depth2, i = set(), 0, 0
        while i < len(args):
            ch = args[i]
            if ch in '([{':
                depth2 += 1
            elif ch in ')]}':
                depth2 -= 1
            elif depth2 == 0:
                am = re.match(r'\s*(\w+)\s*:(?!:)', args[i:])
                if am and (i == 0 or args[i - 1] in ',\n' or args[:i].strip() == ''):
                    given.add(am.group(1))
                    i += am.end() - 1
            i += 1

        for g in given:
            if g not in params and g != 'key':
                report(path, m.start(),
                       f'{cname}{"." + ctor if ctor else ""} has no named '
                       f'parameter `{g}`')

        # `ProfitLoss() => _ProfitLossView(...)` inside a switch is an object
        # pattern, not a call — it matches any instance and supplies nothing.
        # Reporting its every required parameter as missing is nonsense.
        after = text[k + 1:k + 8].lstrip()
        if not args.strip() and (after.startswith('=>') or
                                 after.startswith('when')):
            continue

        for pname, req in params.items():
            if req and pname not in given:
                report(path, m.start(),
                       f'{cname}{"." + ctor if ctor else ""} is missing '
                       f'required `{pname}`')


# ── 3: static member access on repo classes ──────────────────────────

STATIC_ACCESS_RE = re.compile(r'(?<![\w.$])([A-Z]\w+)\.(\w+)')

for path, text in CLEAN.items():
    for m in STATIC_ACCESS_RE.finditer(text):
        cname, member = m.group(1), m.group(2)
        # A call — `X.foo(...)` — could be a named constructor or a static
        # method; both live in .static, so no special case is needed. But the
        # lookahead must not be part of the pattern, or the regex backtracks
        # `\w+` a character at a time until it succeeds. That produced
        # thousands of phantom findings for members like `fromJso`.
        after = text[m.end():m.end() + 1]
        if after == '.':
            continue          # X.y.z — y is likely a library prefix
        info = unique(cname)
        if info is None:
            continue
        if member in info.static:
            continue
        if member in ('new', 'values', 'fromJson'):
            continue
        if member in info.instance:
            report(path, m.start(),
                   f'`{cname}.{member}` is an instance member, not a static')
        else:
            report(path, m.start(), f'{cname} has no static member `{member}`')


# ── 4: instance member access, where the type is locally declared ────

DECL_RES = [
    re.compile(r'\bfinal\s+([A-Z]\w+)\??\s+(\w+)\s*[;=]'),
    re.compile(r'\blate\s+(?:final\s+)?([A-Z]\w+)\??\s+(\w+)\s*[;=]'),
    re.compile(r'^\s{2,}([A-Z]\w+)\??\s+(\w+)\s*;', re.M),
]

UNTYPED_RE = re.compile(r'\b(?:final|var|const)\s+(\w+)\s*=')

# A closure parameter is a binding too: `validator: (value) => ...`
# shadows any field of that name, and reading the field's type there
# is how `PlatformUser has no member trim` came about.
LAMBDA_RE = re.compile(r'\(\s*(\w+)(?:\s*,\s*(\w+))?\s*\)\s*(?:async\s*)?[={]')

# So is a loop variable. `for (final line in result.unmatchedLines)` binds
# `line` to whatever that list holds, which is rarely the type some field
# of the same name happens to have elsewhere in the file.
FOREACH_RE = re.compile(r'\bfor\s*\(\s*(?:final\s+|var\s+)?(?:[\w<>?, ]+\s+)?(\w+)\s+in\b')

for path, text in CLEAN.items():
    candidates = defaultdict(set)
    for pat in DECL_RES:
        for m in pat.finditer(text):
            tname, vname = m.group(1), m.group(2)
            if unique(tname) is not None:
                candidates[vname].add(tname)

    if not candidates:
        continue

    # A name also bound without a type — an inferred local or a closure
    # parameter — could be anything, so the typed binding cannot be trusted
    # to be the one in scope at any given use.
    for m in UNTYPED_RE.finditer(text):
        candidates.pop(m.group(1), None)
    for m in LAMBDA_RE.finditer(text):
        for g in m.groups():
            if g:
                candidates.pop(g, None)
    for m in FOREACH_RE.finditer(text):
        candidates.pop(m.group(1), None)

    types = {v: next(iter(t)) for v, t in candidates.items() if len(t) == 1}
    if not types:
        continue

    # One pass over the file collecting every `receiver.member`, rather than a
    # scan per variable — the naive version was quadratic and took minutes.
    for m in re.finditer(r'(?<![\w.$])(\w+)(?:!|\?)?\.(\w+)', text):
        vname, member = m.group(1), m.group(2)
        tname = types.get(vname)
        if tname is None:
            continue
        info = unique(tname)
        if info is None:
            continue
        # only trust classes whose whole hierarchy is declared in this repo
        if any(unique(s) is None for s in info.supers):
            continue
        if member in info.instance or member in info.static:
            continue
        if member in ('toString', 'hashCode', 'runtimeType', 'noSuchMethod'):
            continue
        report(path, m.start(),
               f'{tname} has no member `{member}` (via `{vname}`)')


# ── output ───────────────────────────────────────────────────────────

FINDINGS.sort()
seen = set()
for path, line, msg in FINDINGS:
    key = (path, line, msg)
    if key in seen:
        continue
    seen.add(key)
    print(f'{path}:{line}  {msg}')

print(f'\n{len(seen)} finding(s) across {len(SRC)} files, '
      f'{len(CLASSES)} classes indexed')
sys.exit(1 if seen else 0)
