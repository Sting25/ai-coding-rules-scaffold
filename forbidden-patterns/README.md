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
accepts on both BSD and GNU. A few notes:

- **Word boundaries:** `\b`. Works on GNU grep (Linux) and modern macOS
  BSD grep. The BSD-specific `[[:<:]]` / `[[:>:]]` form is *not*
  supported by GNU grep, so don't use it. Truly minimal greps
  (busybox / Alpine) may not support `\b` either; this scaffold
  targets developer workstations and standard CI runners, where `\b`
  works reliably.
- **Whitespace:** `\s`. Same portability story as `\b`. POSIX `[[:space:]]`
  also works and is a fine drop-in if you prefer it.
- **Alternation:** patterns can contain literal `|` since the field
  separator is TAB. `(TODO|FIXME|XXX)` works in one line.
- **Tabs in patterns:** not supported (a TAB inside the regex would split
  the field). Use `\s` or `[[:space:]]` for whitespace matching.

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
