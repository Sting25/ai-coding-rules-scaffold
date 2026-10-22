# forbidden-patterns/

Pattern files consumed by `.githooks/lib/check-patterns` and
`.githooks/lib/check-secrets`. Same format, different scope:

| File           | Scans                                                          | Case-sensitive |
| -------------- | -------------------------------------------------------------- | -------------- |
| `backend.txt`  | `*.py`                                                         | yes            |
| `frontend.txt` | `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.vue`, `*.svelte`          | yes            |
| `shell.txt`    | `*.sh`, `*.bash`                                               | yes            |
| `php.txt`      | `*.php`, `*.phtml`, …                                          | yes            |
| `go.txt`       | `*.go`                                                         | yes            |
| `rust.txt`     | `*.rs`                                                         | yes            |
| `java.txt`     | `*.java`                                                       | yes            |
| `kotlin.txt`   | `*.kt`, `*.kts`                                                | yes            |
| `ruby.txt`     | `*.rb`, `*.rake`                                               | yes            |
| `secrets.txt`  | all tracked files (every staged blob, regardless of extension) | no             |

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

### Scoping a run to a subset of pattern files

`check-patterns` scans every discovered file by default. A caller that runs
more than one tier (say, security rules against the whole tree and everything
else against changed files only) can select pattern files by basename:

```sh
CHECK_PATTERNS_INCLUDE="security.txt" .githooks/lib/check-patterns <whole-tree.nul
CHECK_PATTERNS_EXCLUDE="security.txt" .githooks/lib/check-patterns <changed.nul
```

Both variables take space-separated basenames and match whole names, so
`frontend.txt` never selects `frontend-security.txt`. An `INCLUDE` that
matches no file prints a warning to stderr instead of silently scanning
nothing. The shipped pre-commit hook and CI workflow leave both unset.

## Format

```
<regex><TAB><description>
```

One pattern per line. Field separator is a literal TAB. Lines starting with
`#` are comments and skipped.

### Per-rule path excludes

A rule line may carry an optional third TAB field of comma-separated path
globs that the rule does not scan:

```
<regex><TAB><description><TAB>exclude=tests/*,scripts/*
```

The print-style rules ship with per-language defaults so CLI programs, scripts
and tests are not blocked: `backend.txt` `print()` excludes
`tests/*,test/*,scripts/*,bin/*,examples/*`; `go.txt` `fmt.Print*` and
`println` exclude `*_test.go,tests/*,scripts/*,cmd/*,examples/*`; `rust.txt`
`println!`/`print!`/`eprintln!`/`eprint!` exclude
`tests/*,benches/*,examples/*,src/main.rs,src/bin/*`. A glob
is a shell `case` pattern on the repo-relative path, where `*` also matches `/`
(`tests/*` is the top-level `tests/` at any depth below it; use `*/tests/*` for
a nested one). Only a field starting `exclude=` is read as one, a glob cannot
contain a comma or a TAB, and `secrets.txt` takes none (secret scanning is never
path-exempt).

A project adds its own paths in `.scaffold.toml`, in the rule's table, keyed
`"<patternfile-stem>/<description>"` like `disabled` and `severity`. The array
is single-line, and its entries are added to the shipped defaults:

```toml
[rules."backend/Use structlog (or the project's logger), not print()"]
exclude = ["app/cli/*"]
```

An excluded path is skipped for that rule only. Order per finding: a
`scaffold-allow` marker on the line, then the path exclude, then the linter
dedupe below, then the rule's `disabled` / `severity` setting.

### Linter dedupe

A rule line may also carry `linter=eslint:<token>` or `linter=ruff:<token>`, in
either order with `exclude=`. `|` separates alternative tokens, any one of which
suffices:

```
<regex><TAB><description><TAB>linter=eslint:no-debugger|recommended
```

It marks a rule that the scaffold's own linter config already enforces:
`console.log` (`no-console`), `debugger` (`no-debugger`), `@ts-ignore` and
`@ts-nocheck` (`ban-ts-comment`) for eslint, `os.path.join` (`PTH118`) and a bare
`# type: ignore` (`PGH003`) for ruff. Keeping both layers meant a legitimate case
needed two suppressions (`// eslint-disable-next-line` plus `scaffold-allow`), and
a linter per-file ignore never reached the regex.

check-patterns skips such a rule for a file when that linter will lint it with
the rule on. Three things must hold. The config is present (`ruff.toml` or
`pyproject.toml`; `eslint.config.js` or `package.json`). A token is in the
linter's config file (`ruff.toml`, `.ruff.toml` or `pyproject.toml`;
`eslint.config.js`, `.cjs`, `.mjs` or `.eslintrc*`), found by a plain substring
search; the shipped fields are `eslint:no-console`,
`eslint:no-debugger|recommended`, `eslint:ban-ts-comment|strictTypeChecked`,
`ruff:PTH` and `ruff:PGH`, so a bare `package.json` or `pyproject.toml` whose
linter runs on its defaults keeps the regex. And the file is one the linter is
handed (`.py` for ruff; `.ts .tsx .js .jsx .cjs .mjs` for eslint,
case-sensitive). A name other than `eslint` or `ruff`, or a field with no token,
never skips anything.

Locally the linter must also be installed (a ruff in the active or project
virtualenv, on `PATH`, or `python3 -m ruff`; an eslint that node resolves from
this project's `node_modules`), mirroring pre-commit, so where pre-commit would
print "note: eslint not installed ..." the regex still blocks. Under `--ci` the
binary test is the lint workflow's instead, because its eslint and ruff steps run
in another job: ruff runs whenever its config is present, and eslint whenever
`eslint.config.js` is present or `package.json` names `eslint`.

The test is `scaffold-config linter-runs <name>:<tokens> <path> [--ci]`. The
token search is a substring match, not a parse, so a config that names a rule
only to switch it off still counts. To keep the regex on for one rule
regardless, add `linter-dedupe = false` to its table in `.scaffold.toml`:

```toml
[rules."frontend/Use the project logger, not console.log"]
linter-dedupe = false
```

`secrets.txt` takes no `linter=` field.

### Regex syntax

**Extended Regular Expressions** (ERE) — the dialect that `grep -E`
accepts on every grep implementation we care about (GNU, BSD, busybox).
Patterns in this scaffold use the **POSIX-portable** subset only:

- **Word boundaries:** `(^|[^A-Za-z_])` for word-start, `($|[^A-Za-z0-9_])`
  for word-end. Verbose but works everywhere ERE works. Avoid `\b`
  (GNU + modern BSD only) and `[[:<:]]` / `[[:>:]]` (BSD only — does
  _not_ work on GNU grep, contrary to its POSIX-class-shaped syntax).
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
console.log(banner); // scaffold-allow — pre-init log, before logger ready
```

```md
Example AWS key: AKIAIOSFODNN7EXAMPLE <!-- scaffold-allow docs example -->
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
is language-agnostic because credentials leak from config, docs, scripts,
and code alike.

### Case sensitivity in `secrets.txt`

Rules in `secrets.txt` match **case-insensitively by default**. A rule
prefixed with the literal marker `(?-i)` is matched **case-sensitively**
instead:

```
(?-i)(AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}	AWS access key ID …
```

The marker is a scaffold convention, not regex syntax — POSIX ERE has no
inline flags, so `check-secrets` strips it and translates it into the grep
invocation. Never pass `(?-i)` to grep yourself.

Use it for **token-shaped** rules. Vendor key formats, base64 segments, and
the PEM banner are case-sensitive by specification, so folding case cannot
add a true positive — only false ones. The AWS `ACCA` prefix is composed
entirely of hex characters, so without the marker it matches inside ordinary
SHA-256 digests and fails any repo with a lockfile.

Omit it for **keyword-shaped** rules (`password =`, `secret_key`) and the
URL-scheme rules, which match human-written prose where case genuinely
varies. Omitting the marker is also the pre-existing behaviour, so an older
`secrets.txt` with no markers keeps working unchanged.
