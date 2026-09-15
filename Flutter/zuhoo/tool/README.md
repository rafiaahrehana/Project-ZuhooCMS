# Static checks

Three Python scripts that check this Dart codebase without a Dart SDK.

> **Use `flutter analyze` instead.** These were written when the machine doing
> the parity work had no toolchain. It has one now, and the real analyzer found
> 87 issues these had all reported clean on — 38 of them errors. Most were
> Riverpod 3 API changes that need a type system to see.
>
> These remain useful only where a toolchain genuinely is not available. Do not
> read a clean run as a clean codebase.

Run each from `Flutter/zuhoo`:

```bash
python tool/check_structure.py
python tool/check_usage.py
python tool/check_unused.py
```

Each exits non-zero when it finds something.

## What they check

**`check_structure.py`** — bracket and string balance across every file,
import paths that resolve to a real file, every symbol named in a `show`
clause actually existing in the file it is shown from, imports nothing uses,
and LF line endings.

**`check_usage.py`** — indexes every class declared in the repo and checks
every use of one against its declaration:

- a named argument the constructor does not declare
- a required named argument left out
- a static member the class does not declare
- an instance member the class does not declare, where the receiver's type is
  declared and unambiguous in the same file

**`check_unused.py`** — private declarations nothing references, and locals
assigned but never read.

## What they cannot check

Everything that needs a type system. No type compatibility, no generic
inference, no null-safety flow analysis, no override checking, nothing about
the Flutter or Dart SDK — those classes are invisible here, so any use of one
is skipped rather than guessed at.

**These are not a substitute for `flutter analyze`.** That is not a caution —
it is measured. When the toolchain arrived, these three reported zero and the
real analyzer reported 87. What they missed:

- every Riverpod 3 API change (`valueOrNull` removed, `ProviderListenable` no
  longer exported, `AsyncNotifier.update` colliding with three controllers)
- a member on an SDK type (`Account.name` where the field is `accountName`
  was caught, but only because `Account` is declared here)
- an ambiguous import where two libraries both declare `Shift`
- all 46 lints

They did catch things at the time, and their conservatism was real — they
reported no false positives. But zero from these means "nothing in four narrow
classes", not "clean".

## The bar for a finding

Every check is conservative: anything it cannot resolve with confidence is
skipped rather than guessed at. A wrong finding is worse than a missing one,
because acting on it damages working code.

That bar was set the hard way. A field-name-based null-safety check was
written, produced three findings, and all three were wrong — a record field, a
nullable getter, and an SDK type, each colliding with a same-named field on
some unrelated model. It was deleted rather than shipped; the reasoning is
kept in a comment at the foot of `check_unused.py` so nobody rebuilds it.

Each script's own header records the traps it had to be taught. If you extend
one, verify the new check against deliberately broken code first — several of
these were silently dead at one point, reporting zero because they matched
nothing at all rather than because the code was clean.
