# Components: adopt what you want, no installer required

This file is the catalog of everything the scaffold ships, one entry per
component, written so that a person or an AI agent can pick pieces and apply
them with plain commands. `install.sh` is a convenience that runs the same
copies for you; nothing here needs it.

Every entry has the same shape:

- **What it does** and what it blocks.
- **Blast radius.** `staged files only` means the guard looks at the files in
  the commit being made and nothing else, so it is safe on any existing
  codebase. `project-wide` means a tool runs against the whole tree, and an
  existing codebase can produce thousands of findings on day one (issue #163
  measured 12,235 from one config file). Read that line before copying.
- **Adopt:** the exact commands. Run them from your project root.
- **Verify:** one command that proves the guard is armed, not just present.
- **Remove:** how to take it back out.

Commands assume `$SCAFFOLD` points at a copy of this repository. Pick one:

```sh
# a pinned clone (no Node needed)
git clone --branch v0.17.0 https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
export SCAFFOLD=~/src/ai-coding-rules-scaffold
```

```sh
# or the published npm tarball, unpacked, no clone
cd "$(mktemp -d)" && npm pack ai-coding-rules-scaffold@0.17.0 --silent && tar xzf ai-coding-rules-scaffold-*.tgz
export SCAFFOLD="$PWD/package"
```

The catalog is tested: `tests/cases/38-components-catalog.sh` extracts the
fenced `adopt` and `verify` blocks below, runs them in a throwaway repository,
and fails the suite if any verify step does not prove its guard. If a command
here is wrong, CI is red.

Hand-copied files are yours. The installer's upgrade logic keys off a manifest
it writes; without one, a later `install.sh` run treats your copies as
hand-edited and preserves them. To upgrade a hand-copied component, re-run its
adopt block against a newer `$SCAFFOLD`.

**Before adopting anything on an existing codebase**, measure what it would
flag. `bash "$SCAFFOLD/scaffold-assess.sh"` (or `npx ai-coding-rules-scaffold
assess`, no clone) runs every scanner read-only against your tracked files and
reports findings per component, says "not applicable" for a language you have
no files in, measures the project-wide configs with the tool itself when it is
installed, and writes nothing. Its output names the entry numbers below.

---

## 1. Commit guard core

Six scanners plus the hook that runs them, the shared config reader, and the
two pattern files every project wants. They are one component because the
hook calls all six and fails loudly on a missing one, and because all six are
cheap and staged-only.

| Scanner           | Blocks                                                                                 |
| ----------------- | -------------------------------------------------------------------------------------- |
| check-secrets     | credential-shaped strings: 42 rules covering AWS, GitHub, Slack, private keys and more |
| check-filenames   | committing `.env`, `id_rsa`, `*.pem`, keystores, by name                               |
| check-patterns    | forbidden source patterns from `.forbidden-patterns/*.txt`, per language (see entry 2) |
| check-hygiene     | invisible unicode, bidi controls, merge-conflict markers, other smuggling              |
| check-large-files | files over 512,000 bytes (override in `.scaffold.toml`)                                |
| check-size        | files over 500 lines (override in `.scaffold.toml`)                                    |

**Blast radius:** staged files only. Safe on any existing codebase. Existing
committed secrets are not touched; see README "Already have commit history?"
for a one-time scan.

**Prerequisites:** bash, git. No other tool.

```sh adopt=core
mkdir -p .githooks/lib .forbidden-patterns
cp "$SCAFFOLD/githooks/pre-commit.template" .githooks/pre-commit
for c in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene scaffold-config; do
  cp "$SCAFFOLD/githooks/lib/$c.template" ".githooks/lib/$c"
done
chmod +x .githooks/pre-commit .githooks/lib/*
cp "$SCAFFOLD/forbidden-patterns/secrets.txt.template" .forbidden-patterns/secrets.txt
cp "$SCAFFOLD/forbidden-patterns/shell.txt.template"   .forbidden-patterns/shell.txt
git config core.hooksPath .githooks
```

If `git config --get core.hooksPath` already pointed somewhere (Husky,
lefthook, a company hook set), do not overwrite it: chain `.githooks/pre-commit`
from your existing pre-commit instead. README "Pairing with Husky / lefthook"
shows both.

The verify step stages a file named `.env` and an oversize file, and asserts
the commit is refused. It leaves your index as it found it.

```sh verify=core
set -e
git stash list >/dev/null
printf 'x=1\n' > .env.scaffold-verify && mv .env.scaffold-verify .env
head -c 600000 /dev/zero > scaffold-verify.bin
git add -f .env scaffold-verify.bin
if git -c commit.gpgsign=false commit -q -m "scaffold verify" >/dev/null 2>&1; then
  git reset -q --soft HEAD~1; git reset -q .env scaffold-verify.bin; rm -f .env scaffold-verify.bin
  echo "NOT ARMED: the commit with .env and a 600 KB file went through"; exit 1
fi
git reset -q .env scaffold-verify.bin; rm -f .env scaffold-verify.bin
echo "verified: commit guard core refused .env and a 600 KB file"
```

```sh remove=core
git config --unset core.hooksPath
rm -rf .githooks .forbidden-patterns
```

## 2. Language pattern files

`check-patterns` scans whatever `.forbidden-patterns/*.txt` files exist. Each
file names the extensions it applies to in a `# scaffold-extensions:` header.
Adopt the languages you write; a language you have no files in is simply
never scanned.

| File         | Extensions           | Blocks (examples)                                                                          |
| ------------ | -------------------- | ------------------------------------------------------------------------------------------ |
| backend.txt  | py                   | `print(`, `breakpoint()`, `pdb.set_trace()`, `verify=False`                                |
| frontend.txt | js jsx ts tsx svelte | `console.log`, `debugger`, raw `innerHTML` assignment                                      |
| go.txt       | go                   | `InsecureSkipVerify: true`, `fmt.Println` debug prints                                     |
| java.txt     | java                 | `Runtime.exec` on a built string, an empty `checkServerTrusted()`, debug prints            |
| kotlin.txt   | kt kts               | same surfaces as Java, Kotlin syntax                                                       |
| php.txt      | php                  | cURL TLS verification switched off, `eval`, `var_dump`, `dd()`                             |
| ruby.txt     | rb                   | `eval`, `Marshal.load` of untrusted input, `binding.pry`                                   |
| rust.txt     | rs                   | `dbg!`, `println!` debug prints (`unwrap()` and `unsafe` rules ship commented out, opt-in) |

Every security rule in these files was measured against a real third-party
corpus before shipping (CHANGELOG v0.16.0). Rules that could not be made
precise are present but commented out, with a note on when to enable them.

**Blast radius:** staged files only. A rule that fires on your existing code
fires only when you next touch that file. To see how often that would be,
run the assess script, or disable a single rule in `.scaffold.toml` (entry 13)
rather than deleting the file.

**Prerequisites:** entry 1.

```sh adopt=patterns
cp "$SCAFFOLD/forbidden-patterns/backend.txt.template"  .forbidden-patterns/backend.txt
cp "$SCAFFOLD/forbidden-patterns/frontend.txt.template" .forbidden-patterns/frontend.txt
# add any of: go java kotlin php ruby rust
```

```sh verify=patterns
set -e
printf 'import os\nbreakpoint()\n' > scaffold_verify.py
git add scaffold_verify.py
if git -c commit.gpgsign=false commit -q -m "scaffold verify" >/dev/null 2>&1; then
  git reset -q --soft HEAD~1; git reset -q scaffold_verify.py; rm -f scaffold_verify.py
  echo "NOT ARMED: a breakpoint() in a .py file was committed"; exit 1
fi
git reset -q scaffold_verify.py; rm -f scaffold_verify.py
echo "verified: backend.txt refused breakpoint() in a staged .py file"
```

```sh remove=patterns
rm -f .forbidden-patterns/backend.txt .forbidden-patterns/frontend.txt
```

## 3. CI mirror of the commit guard

`lint.yml` runs the same six scanners server-side on every pull request and
push, using the same scripts in `.githooks/lib/`, so the hook and CI cannot
drift. Secrets and filenames are scanned whole-tree; the quality gates run on
changed files only. It also runs ruff, eslint, prettier, tsc and phpcs when
their configs are present (entries 6 to 12 decide that).

**Blast radius:** changed files for the scanners; whole tree for the secrets
and filename scans (a leaked credential anywhere fails the job, which is the
point). The linters follow their own configs' scope.

**Prerequisites:** entry 1, GitHub Actions.

```sh adopt=ci-lint
mkdir -p .github/workflows
cp "$SCAFFOLD/.github/workflows/lint.yml.template" .github/workflows/lint.yml
cp "$SCAFFOLD/githooks/lib/ci-changed-files.template" .githooks/lib/ci-changed-files
chmod +x .githooks/lib/ci-changed-files
```

A workflow can only be proven by a run. This verify step checks the file is a
valid workflow (with actionlint if you have it) and that it calls every scanner
the hook calls, so hook and CI agree before the first push.

```sh verify=ci-lint
set -e
for c in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene; do
  grep -q "lib/$c" .github/workflows/lint.yml || { echo "NOT MIRRORED: lint.yml does not call $c"; exit 1; }
done
if command -v actionlint >/dev/null 2>&1; then actionlint -shellcheck= -pyflakes= .github/workflows/lint.yml; fi
echo "verified: lint.yml calls all six scanners the hook calls"
```

```sh remove=ci-lint
rm -f .github/workflows/lint.yml .githooks/lib/ci-changed-files
```

## 4. Tests in CI

`tests.yml` runs pytest and/or vitest on every pull request and push, with no
coverage threshold. `coverage.yml` is the stricter alternative: it fails a PR
whose changed lines are not covered.

**Blast radius:** runs your whole test suite in CI. If the suite is red today,
CI is red tomorrow. That is information, not a scaffold bug, but know it before
you adopt.

**Prerequisites:** a test runner the workflow can invoke (`pytest`, `vitest`).
`coverage.yml` also needs the coverage config from entries 8 and 11.

```sh adopt=ci-tests
mkdir -p .github/workflows
cp "$SCAFFOLD/.github/workflows/tests.yml.template" .github/workflows/tests.yml
# stricter: replace with coverage.yml instead of tests.yml
# cp "$SCAFFOLD/.github/workflows/coverage.yml.template" .github/workflows/coverage.yml
```

```sh verify=ci-tests
set -e
test -f .github/workflows/tests.yml
if command -v actionlint >/dev/null 2>&1; then actionlint -shellcheck= -pyflakes= .github/workflows/tests.yml; fi
echo "verified: tests.yml is present and valid"
```

```sh remove=ci-tests
rm -f .github/workflows/tests.yml .github/workflows/coverage.yml
```

## 5. The rules documents and the agent entry point

`coding-rules.md` and `operational-rules.md` are the rules an AI agent follows
in your codebase; `AGENTS.md` is the short always-loaded summary that points at
them. These are documents, not code. They are the most-adopted piece of the
scaffold and need nothing else. README "Use the rules without the rest of the
scaffold" covers Claude Code, Cursor, Aider and Cline wiring.

**Blast radius:** none on your files. They change what an agent does next.

```sh adopt=rules
cp "$SCAFFOLD/coding-rules.md"      coding-rules.md
cp "$SCAFFOLD/operational-rules.md" operational-rules.md
[ -f AGENTS.md ] || cp "$SCAFFOLD/AGENTS.md.template" AGENTS.md
# Claude Code: make CLAUDE.md load them on session start
[ -f CLAUDE.md ] && grep -q '@AGENTS.md' CLAUDE.md || printf '@AGENTS.md\n@coding-rules.md\n' >> CLAUDE.md
```

```sh verify=rules
set -e
test -s coding-rules.md && test -s operational-rules.md && test -s AGENTS.md
grep -q '@AGENTS.md' CLAUDE.md
echo "verified: rules documents present and CLAUDE.md imports AGENTS.md"
```

```sh remove=rules
rm -f coding-rules.md operational-rules.md AGENTS.md
# then delete the two @ lines from CLAUDE.md
```

## 6. ruff config (Python lint)

`ruff.toml` is an opinionated ruleset: security (S), bugbear (B), async (ASYNC),
logging (G, LOG), blind-except (BLE), and more. The hook lints staged `.py`
files with it; `lint.yml` lints changed files.

**Blast radius: project-wide config, staged-file enforcement.** The config
governs every `.py` file, but the hook and CI only run ruff on the files in the
change, so an existing codebase is not blocked wholesale. Expect the first
touch of an old file to surface its findings. Measure first:
`ruff check --config "$SCAFFOLD/ruff.toml.template" .` prints the count with
nothing copied.

**Prerequisites:** entry 1 for the hook to use it; `ruff` on PATH or in a venv.

```sh adopt=ruff
[ -f ruff.toml ] && echo "ruff.toml exists, merge by hand: $SCAFFOLD/ruff.toml.template" || cp "$SCAFFOLD/ruff.toml.template" ruff.toml
```

```sh verify=ruff
set -e
test -f ruff.toml
if command -v ruff >/dev/null 2>&1 || python3 -m ruff --version >/dev/null 2>&1; then
  ruff check --config ruff.toml --quiet --exit-zero . >/dev/null || python3 -m ruff check --config ruff.toml --quiet --exit-zero . >/dev/null
  echo "verified: ruff loads ruff.toml"
else
  echo "verified: ruff.toml present (ruff not installed here, so it was not exercised)"
fi
```

```sh remove=ruff
rm -f ruff.toml
```

## 7. pytest config

`pytest.ini` sets `testpaths = tests` and strict markers.

**Blast radius: project-wide.** A root `pytest.ini` overrides any nested one
and, if `tests/` does not exist, pytest collects from the repo root. The
installer refuses to write it when a nested pytest config exists; do the same
check by hand.

```sh adopt=pytest
if [ -f pytest.ini ] || [ -f pyproject.toml ] && grep -q '\[tool.pytest' pyproject.toml 2>/dev/null; then
  echo "a pytest config already exists, merge by hand: $SCAFFOLD/pytest.ini.template"
else
  cp "$SCAFFOLD/pytest.ini.template" pytest.ini
  [ -d tests ] || echo "note: pytest.ini points testpaths at ./tests/, which does not exist yet"
fi
```

```sh verify=pytest
set -e
test -f pytest.ini || { echo "pytest.ini not written (a config already existed)"; exit 0; }
grep -q 'testpaths' pytest.ini
echo "verified: pytest.ini present"
```

```sh remove=pytest
rm -f pytest.ini
```

## 8. coverage config (Python)

`.coveragerc` sets branch coverage and the omit list `coverage.yml` expects.

**Blast radius:** none until `coverage.yml` (entry 4) or a local coverage run
reads it.

```sh adopt=coveragerc
[ -f .coveragerc ] || cp "$SCAFFOLD/.coveragerc.template" .coveragerc
```

```sh verify=coveragerc
set -e
test -f .coveragerc && echo "verified: .coveragerc present"
```

```sh remove=coveragerc
rm -f .coveragerc
```

## 9. eslint config (JS/TS lint)

`eslint.config.js` is a flat config with type-aware rules (`no-floating-promises`,
`no-explicit-any`, security plugin). It derives its ignore list from
`.gitignore`, which is why the doctor and the hook guard `.gitignore` against
being used to un-lint source. The hook lints staged JS/TS files.

**Blast radius: project-wide config, staged-file enforcement**, same as ruff.
Measure first: `npx eslint -c "$SCAFFOLD/eslint.config.js.template" .` with the
plugins installed.

**Prerequisites:** `eslint`, `typescript-eslint` and `eslint-plugin-security`
in `node_modules`. The config's header lists the exact packages.

```sh adopt=eslint
[ -f eslint.config.js ] && echo "eslint.config.js exists, merge by hand" || cp "$SCAFFOLD/eslint.config.js.template" eslint.config.js
```

```sh verify=eslint
set -e
test -f eslint.config.js && echo "verified: eslint.config.js present (run npx eslint . to exercise it)"
```

```sh remove=eslint
rm -f eslint.config.js
```

## 10. tsconfig (TypeScript type check)

`tsconfig.json` enables `strict`, `exactOptionalPropertyTypes` and
`noUncheckedIndexedAccess`, with no `jsx`, no DOM lib and no path aliases.

**Blast radius: PROJECT-WIDE, and the hook runs it project-wide.** When a root
`tsconfig.json` exists and a commit touches any JS/TS file, the hook runs
`tsc --noEmit` on the whole tree, because tsc ignores its config when given
file arguments. On an existing codebase that was not written for these
options, every commit is blocked until the whole tree passes. Issue #163
measured 12,235 errors in a workspaces monorepo from this one file.

Do not adopt this on an existing codebase unless the measurement below is zero
or you intend to fix everything it reports. Never adopt it at the root of a
monorepo that has per-package tsconfigs; those already do the job.

Measure first, nothing copied:
`npx tsc --noEmit -p "$SCAFFOLD/tsconfig.json.template" 2>&1 | grep -c 'error TS'`

```sh adopt=tsconfig
if [ -f tsconfig.json ]; then echo "tsconfig.json exists, leave it";
elif grep -q '"workspaces"' package.json 2>/dev/null || [ -f pnpm-workspace.yaml ]; then echo "workspaces monorepo: do not add a root tsconfig.json";
else cp "$SCAFFOLD/tsconfig.json.template" tsconfig.json; fi
```

```sh verify=tsconfig
set -e
[ -f tsconfig.json ] || { echo "tsconfig.json not written (existing config or monorepo)"; exit 0; }
echo "verified: tsconfig.json present; the hook will now type-check the whole tree on JS/TS commits"
```

```sh remove=tsconfig
rm -f tsconfig.json
```

## 11. prettier, vitest, npm cooldown (frontend extras)

- `.prettierrc.json` and `.prettierignore`: the hook runs `prettier --check` on
  staged JS/TS when a config is present. Staged files only.
- `vitest.config.ts`: coverage settings `coverage.yml` reads. No effect until a
  test run.
- `.npmrc` with `min-release-age=7`: npm refuses packages published in the last
  seven days (supply-chain cooldown). **Silently changes dependency resolution**
  on every machine that has the file; needs npm 11.10 or newer, older npm
  ignores it with a warning. Adopt deliberately and commit it, so it is visible.

```sh adopt=frontend-extras
[ -f .prettierrc.json ] || cp "$SCAFFOLD/.prettierrc.json.template" .prettierrc.json
[ -f .prettierignore ]  || cp "$SCAFFOLD/.prettierignore.template"  .prettierignore
[ -f vitest.config.ts ] || cp "$SCAFFOLD/vitest.config.ts.template" vitest.config.ts
# opt-in, read its header first:
# cp "$SCAFFOLD/.npmrc.template" .npmrc
```

```sh verify=frontend-extras
set -e
test -f .prettierrc.json && test -f .prettierignore && test -f vitest.config.ts
echo "verified: prettier and vitest configs present"
```

```sh remove=frontend-extras
rm -f .prettierrc.json .prettierignore vitest.config.ts .npmrc
```

## 12. Conventional Commits check

`commit-msg` rejects a commit whose subject is not `type(scope): description`
with a known type. Merge, revert, fixup and squash subjects are exempt.

**Blast radius:** every new commit message. Existing history is untouched.

**Prerequisites:** entry 1 (uses the same `core.hooksPath`).

```sh adopt=commit-msg
cp "$SCAFFOLD/githooks/commit-msg.template" .githooks/commit-msg
chmod +x .githooks/commit-msg
```

```sh verify=commit-msg
set -e
printf 'ok\n' > scaffold-verify.txt && git add scaffold-verify.txt
if git -c commit.gpgsign=false commit -q -m "not a conventional subject" >/dev/null 2>&1; then
  git reset -q --soft HEAD~1; git reset -q scaffold-verify.txt; rm -f scaffold-verify.txt
  echo "NOT ARMED: a non-conventional subject was accepted"; exit 1
fi
git reset -q scaffold-verify.txt; rm -f scaffold-verify.txt
echo "verified: commit-msg refused a non-conventional subject"
```

```sh remove=commit-msg
rm -f .githooks/commit-msg
```

## 13. Per-project overrides

`.scaffold.toml` turns a single rule down to `warn` or off, or raises the size
caps, with a recorded reason. `scaffold-audit` lists every active override so
they do not accumulate invisibly. Prefer fixing the file; use this for a
genuine false positive.

**Blast radius:** loosens the guards you name, nothing else.

```sh adopt=overrides
[ -f .scaffold.toml ] || cp "$SCAFFOLD/.scaffold.toml.template" .scaffold.toml
cp "$SCAFFOLD/githooks/lib/scaffold-audit.template" .githooks/lib/scaffold-audit
chmod +x .githooks/lib/scaffold-audit
```

```sh verify=overrides
set -e
test -f .scaffold.toml
.githooks/lib/scaffold-audit >/dev/null
echo "verified: .scaffold.toml present and scaffold-audit runs"
```

```sh remove=overrides
rm -f .scaffold.toml .githooks/lib/scaffold-audit
```

## 14. Project-local checks

Any executable you place in `.githooks/local.d/` runs from the hook and from
`lint.yml` under the same contract as the shipped scanners: NUL-separated
staged paths on stdin, non-zero exit blocks the commit. This is the extension
point; do not edit `pre-commit` itself.

```sh adopt=local-d
mkdir -p .githooks/local.d
cp "$SCAFFOLD/githooks/local.d/README.md.template" .githooks/local.d/README.md
```

```sh verify=local-d
set -e
test -f .githooks/local.d/README.md && echo "verified: local.d extension point present"
```

```sh remove=local-d
rm -rf .githooks/local.d
```

## 15. AI agent guardrails (Claude Code, Cursor)

`agent-precheck` is a PreToolUse hook: it refuses an agent's attempt to write a
credential-shaped string, to run a dangerous shell pattern, or to read a
credential file into context. `.claude/settings.json` wires it for Claude Code;
`.cursor/hooks.json` for Cursor.

**Blast radius:** the agent's tool calls in this repo. No effect on commits or
files.

**Prerequisites:** entry 1's `secrets.txt` and `shell.txt` (the hook reads
them), `jq` on PATH (fails open without it, and says so).

```sh adopt=agent-guard
cp "$SCAFFOLD/githooks/lib/agent-precheck.template" .githooks/lib/agent-precheck
chmod +x .githooks/lib/agent-precheck
mkdir -p .claude
[ -f .claude/settings.json ] && echo ".claude/settings.json exists, merge the hooks key from $SCAFFOLD/claude-settings.json.template" || cp "$SCAFFOLD/claude-settings.json.template" .claude/settings.json
# Cursor instead of, or as well as:
# mkdir -p .cursor && cp "$SCAFFOLD/cursor-hooks.json.template" .cursor/hooks.json
# cp "$SCAFFOLD/githooks/lib/credential-read-patterns.txt.template" .githooks/lib/credential-read-patterns.txt
```

```sh verify=agent-guard
set -e
test -x .githooks/lib/agent-precheck
grep -q 'agent-precheck' .claude/settings.json
echo "verified: agent-precheck present and referenced from .claude/settings.json"
```

```sh remove=agent-guard
rm -f .githooks/lib/agent-precheck .githooks/lib/credential-read-patterns.txt
# then delete the hooks entry from .claude/settings.json or .cursor/hooks.json
```

## 16. gitleaks (second secret scanner)

`check-gitleaks` runs the gitleaks binary on staged files as a second opinion
next to `check-secrets`; the hook runs it only when the file exists.
`gitleaks.yml` is the CI gate, which a developer cannot skip.

**Blast radius:** staged files locally; whole history in CI on the first run.

**Prerequisites:** `gitleaks` on PATH for the local pass (skips loudly if
absent); GitHub Actions for the CI gate.

```sh adopt=gitleaks
cp "$SCAFFOLD/githooks/lib/check-gitleaks.template" .githooks/lib/check-gitleaks
chmod +x .githooks/lib/check-gitleaks
mkdir -p .github/workflows
cp "$SCAFFOLD/.github/workflows/gitleaks.yml.template" .github/workflows/gitleaks.yml
```

```sh verify=gitleaks
set -e
test -x .githooks/lib/check-gitleaks && test -f .github/workflows/gitleaks.yml
echo "verified: gitleaks local pass and CI gate present"
```

```sh remove=gitleaks
rm -f .githooks/lib/check-gitleaks .github/workflows/gitleaks.yml
```

## 17. Supply-chain CI gates

Each is one workflow file, each adds a third-party dependency, so each is a
separate decision.

- `dependency-review.yml`: fails a PR that adds a dependency with a known
  advisory. Needs GitHub Advanced Security on private repos, or it errors.
- `zizmor.yml`: static audit of your own GitHub Actions workflows (unpinned
  actions, credential persistence, over-broad permissions).
- `socket-security.yml`: checks a newly added package is legitimate before it
  is installed.

**Blast radius:** CI only, and only on the events each workflow watches.

```sh adopt=supply-chain-ci
mkdir -p .github/workflows
cp "$SCAFFOLD/.github/workflows/dependency-review.yml.template" .github/workflows/dependency-review.yml
cp "$SCAFFOLD/.github/workflows/zizmor.yml.template"            .github/workflows/zizmor.yml
# cp "$SCAFFOLD/.github/workflows/socket-security.yml.template" .github/workflows/socket-security.yml
```

```sh verify=supply-chain-ci
set -e
test -f .github/workflows/dependency-review.yml && test -f .github/workflows/zizmor.yml
echo "verified: dependency-review and zizmor workflows present"
```

```sh remove=supply-chain-ci
rm -f .github/workflows/dependency-review.yml .github/workflows/zizmor.yml .github/workflows/socket-security.yml
```

## 18. Test-integrity gate (red-green and mutation)

`check-red-green` runs every new test against the PR's base commit and requires
it to fail there, so a test that could never fail cannot ship. An exemption
marker exists for characterization tests. `check-mutation-diff` mutates the
changed lines and warns about survivors; advisory, never fails the job.

**Blast radius:** every PR that adds a test. Register the marker in
`pytest.ini` (the template already does). Make `test-guard` a required status
check, or an agent that can merge will route around it.

**Prerequisites:** Python and pytest for the gate; CI installs `mutmut`.

```sh adopt=test-guard
cp "$SCAFFOLD/githooks/lib/check-red-green.template"     .githooks/lib/check-red-green
cp "$SCAFFOLD/githooks/lib/check-mutation-diff.template" .githooks/lib/check-mutation-diff
chmod +x .githooks/lib/check-red-green .githooks/lib/check-mutation-diff
mkdir -p .github/workflows
cp "$SCAFFOLD/.github/workflows/test-guard.yml.template" .github/workflows/test-guard.yml
grep -q 'test-guard:begin' coding-rules.md 2>/dev/null || cat "$SCAFFOLD/coding-rules-test-guard.md" >> coding-rules.md
```

```sh verify=test-guard
set -e
test -x .githooks/lib/check-red-green && test -f .github/workflows/test-guard.yml
grep -q 'test-guard:begin' coding-rules.md
echo "verified: test-guard gate present and its rules section is in coding-rules.md"
```

```sh remove=test-guard
rm -f .githooks/lib/check-red-green .githooks/lib/check-mutation-diff .github/workflows/test-guard.yml
# then delete the test-guard:begin ... test-guard:end block from coding-rules.md
```

## 19. Claude Code skill (on-demand rules loading)

A skill that loads `coding-rules.md` and `operational-rules.md` when a task
needs them, complementing the always-loaded `AGENTS.md`.

```sh adopt=claude-skill
mkdir -p .claude/skills/coding-rules
cp "$SCAFFOLD/claude-skill/coding-rules/SKILL.md.template" .claude/skills/coding-rules/SKILL.md
```

```sh verify=claude-skill
set -e
test -s .claude/skills/coding-rules/SKILL.md && echo "verified: coding-rules skill present"
```

```sh remove=claude-skill
rm -rf .claude/skills/coding-rules
```

---

## After adopting: check what is armed

`scaffold-doctor.sh` reports, per component, whether it is present, wired and
actually called, and names every gap. It works on hand-copied installs; it
does not need the installer's manifest.

```sh
bash "$SCAFFOLD/scaffold-doctor.sh"      # or: npx ai-coding-rules-scaffold doctor
```

Two things the doctor cannot see: whether CI ran (push and look), and whether
a project-wide config from entries 6 to 10 will flag your existing code (run
the measurement command in that entry first).
