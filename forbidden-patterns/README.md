# forbidden-patterns/

Pattern files consumed by `.githooks/lib/check-patterns` and
`.githooks/lib/check-secrets`. Same format, different scope:

| File           | Scans                                              | Case-sensitive |
|----------------|----------------------------------------------------|----------------|
| `backend.txt`  | `*.py`                                             | yes            |
| `frontend.txt` | `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.vue`, `*.svelte` | yes        |
| `shell.txt`    | `*.sh`, `*.bash`                                   | yes            |
| `php.txt`      | `*.php`, `*.phtml`, …                              | yes            |
| `go.txt`       | `*.go`                                             | yes            |
| `rust.txt`     | `*.rs`                                             | yes            |
| `java.txt`     | `*.java`                                           | yes            |
| `kotlin.txt`   | `*.kt`, `*.kts`                                    | yes            |
| `ruby.txt`     | `*.rb`, `*.rake`                                   | yes            |
| `secrets.txt`  | all tracked text files (binaries / lockfiles excluded) | no         |

`check-patterns` **auto-discovers** every `*.txt` here (except `secrets.txt`,
which is `check-secrets`' domain). Each file declares which extensions it
applies to with a header line:

```
# scaffold-extensions: go
```

so the table above isn't wired into any script — a file's own header is the
source of truth. `backend.txt` / `frontend.txt` / `shell.txt` also have a
built-in fallback mapping, so an older copy without the header still works.
`install.sh` copies a language's file when it detects that language's manifest
(`go.mod`, `Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`,
…), or all of them with `--all-langs`.

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

## Per-line opt-out: `scaffold-allow`

A line is exempt from `check-patterns` and `check-secrets` when it carries a
`scaffold-allow` marker **after a comment leader** — `#`, `//`, `/*`, or
`<!--` (case-insensitive) — at the start of the line or following whitespace.
The comment-leader requirement raises the bar against smuggling the bare
substring inside a string literal (e.g. `token = "scaffold-allow..."` is
**not** exempt). Bare `--` is intentionally **not** a leader: it is a comment
in too few languages to justify the cross-language bypass it opened
(`x = "<secret> -- scaffold-allow"` once suppressed the finding in JS/Python/
shell). Use it as an inline escape valve when a match is intentional — a CLI
entry point that needs `print`, a docs example showing an AWS key prefix, a
test fixture with a synthetic credential. Mirrors the role `# noqa` plays for
ruff. It is **not** a security boundary against a hostile committer (who
controls the file and can also pass `--no-verify`); pair the scaffold with
branch protection and required review.

```python
print("entering CLI")  # scaffold-allow — no logger configured yet
```

```ts
console.log(banner);  // scaffold-allow — pre-init log, before logger ready
```

```md
Example AWS key: AKIAIOSFODNN7EXAMPLE  <!-- scaffold-allow docs example -->
```

The marker only suppresses **its own line**. Other matches in the same
file still fail the check. `check-filenames` and `check-size` ignore the
marker — those rules are file-level, not line-level. Audit usage with
`git grep -i scaffold-allow`.

## Adding a pattern

1. Pick the right file for the language.
2. Test the regex first: `echo 'sample' | grep -E 'your-pattern'` (add
   `-i` for the secrets file).
3. Insert a single TAB between regex and description.
4. Run `./tests/run.sh` from the scaffold root — the harness exercises
   each pattern type.

## Adding a language

No script edit required — that's the point of the `scaffold-extensions` header:

1. Create `.forbidden-patterns/<lang>.txt`.
2. First non-pattern line: `# scaffold-extensions: ext1 ext2` (the file
   extensions to scan, space-separated, no dots).
3. Add `<regex><TAB><description>` lines. Keep active patterns low-false-
   positive — a blocked legitimate commit erodes trust fast. Ship FP-prone
   ones (e.g. Rust `.unwrap()`, Ruby `puts`) commented as opt-in.
4. `check-patterns` picks it up automatically on the next run. Add a fixture
   to `tests/run.sh` and, optionally, a CI linter job (see the commented
   stubs in `.github/workflows/lint.yml`).

## Why split by language

Splitting by language keeps regexes precise: a pattern targeting Python
function calls (`(^|[^A-Za-z_])print[[:space:]]*\(`) shouldn't run against
a TS file containing the string `print` in a comment. The secrets file
is language-agnostic and case-insensitive because credentials leak from
config, docs, scripts, and code alike.
