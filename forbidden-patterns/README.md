# forbidden-patterns/

Pattern files consumed by `.githooks/lib/check-patterns` and
`.githooks/lib/check-secrets`. Three files, same format, different scope:

| File           | Scans                                              | Case-sensitive |
|----------------|----------------------------------------------------|----------------|
| `backend.txt`  | `*.py`                                             | yes            |
| `frontend.txt` | `*.ts`, `*.tsx`, `*.js`, `*.jsx`                   | yes            |
| `shell.txt`    | `*.sh`, `*.bash`                                   | yes            |
| `secrets.txt`  | all tracked text files (binaries / lockfiles excluded) | no         |

## Format

```
<regex><TAB><description>
```

One pattern per line. Field separator is a literal TAB. Lines starting with
`#` are comments and skipped.

### Regex syntax

**Extended Regular Expressions** (ERE) — the dialect that `grep -E`
accepts on every grep implementation we care about (GNU, BSD, busybox).
Patterns in this scaffold use the **POSIX-portable** subset only:

- **Word boundaries:** `(^|[^A-Za-z_])` for word-start, `($|[^A-Za-z0-9_])`
  for word-end. Verbose but works everywhere ERE works. Avoid `\b`
  (GNU + modern BSD only) and `[[:<:]]` / `[[:>:]]` (BSD only — does
  *not* work on GNU grep, contrary to its POSIX-class-shaped syntax).
- **Whitespace:** `[[:space:]]`. POSIX character class, supported on
  every grep. `\s` is a GNU/BSD extension; not used here.
- **Alternation:** patterns can contain literal `|` since the field
  separator is TAB. `(TODO|FIXME|XXX)` works in one line. The word-
  boundary form above also relies on alternation.
- **Tabs in patterns:** not supported (a TAB inside the regex would
  split the field). Use `[[:space:]]` for whitespace matching.

The verbose word-boundary form is a deliberate trade. `\b` is
shorter, but adds a portability assumption we can't verify on every
grep our users run. Spelling the boundary out as a character class
keeps the patterns honest.

### Description

The text after the TAB, printed when the pattern matches alongside the
file:line that triggered it. Keep it actionable — every consumer project
sees this on every blocked commit.

## Adding a pattern

1. Pick the right file (backend / frontend / secrets).
2. Test the regex first: `echo 'sample' | grep -E 'your-pattern'` (add
   `-i` for the secrets file).
3. Insert a single TAB between regex and description.
4. Run `./tests/run.sh` from the scaffold root — the harness exercises
   each pattern type.

## Why three files

Splitting by language keeps regexes precise: a pattern targeting Python
function calls (`[[:<:]]print[[:space:]]*\(`) shouldn't run against a TS
file containing the string `print` in a comment. The secrets file is
language-agnostic and case-insensitive because credentials leak from
config, docs, scripts, and code alike.
