# shellcheck shell=bash
# cases/09-toolchain-clobber.sh — toolchain config delivery + detect/offer, and
# the install-never-clobbers-user-files regression guard (PR #20).
# Sourced into the driver's shell.

# --- toolchain config delivery + detect/offer ------------------------------
# Fresh install (the bootstrap repo removed some of these to isolate the hook
# unit tests). A --both install must drop every auto-by-stack config.
# set -euo pipefail is inherited from the driver, so a failed cd aborts the run.
# shellcheck disable=SC2164
cd "$WORK"
DTMP=$(mktemp -d)
( cd "$DTMP" && git init --quiet && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --both --no-verify ) >"$HOOK_OUT" 2>&1
for f in tsconfig.json .prettierrc.json .prettierignore vitest.config.ts pytest.ini .coveragerc; do
  if [ -f "$DTMP/$f" ]; then
    echo "  ✓ install ships $f (auto by stack)"; PASS=$((PASS + 1))
  else
    echo "  ✗ install did not ship $f"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
done
rm -rf "$DTMP"

# (T) coverage.yml.template is a valid GitHub Actions workflow (opt-in gate).
if command -v actionlint >/dev/null 2>&1; then
  CTMP=$(mktemp -d); mkdir -p "$CTMP/.github/workflows"
  cp "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template" "$CTMP/.github/workflows/coverage.yml"
  if ( cd "$CTMP" && actionlint -shellcheck= -pyflakes= .github/workflows/coverage.yml ) >"$HOOK_OUT" 2>&1; then
    echo "  ✓ coverage.yml.template is a valid GitHub Actions workflow"; PASS=$((PASS + 1))
  else
    echo "  ✗ coverage.yml.template failed actionlint"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$CTMP"
else
  echo "  - skipped coverage.yml validation (actionlint not installed)"
fi

# (T) detect/offer is PRINT-ONLY and non-mutating under non-interactive stdin:
#     no TTY → never auto-runs a package manager, never prompts, never hangs.
OFFTMP=$(mktemp -d)
( cd "$OFFTMP" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend </dev/null ) >"$HOOK_OUT" 2>&1
if grep -q "not installed — run:" "$HOOK_OUT" \
   && ! grep -q "install now with" "$HOOK_OUT" \
   && [ ! -d "$OFFTMP/node_modules" ]; then
  echo "  ✓ detect/offer is print-only + non-mutating without a TTY"; PASS=$((PASS + 1))
else
  echo "  ✗ detect/offer — expected print-only run-hints, no prompt, no install"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFFTMP"

# (T) Vitest config is NOT shipped when the project already uses Jest.
JTMP=$(mktemp -d)
( cd "$JTMP" && git init --quiet && echo '{"name":"x","devDependencies":{"jest":"^29"}}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ ! -f "$JTMP/vitest.config.ts" ] && grep -q "Jest detected" "$HOOK_OUT"; then
  echo "  ✓ vitest.config.ts skipped when Jest is present"; PASS=$((PASS + 1))
else
  echo "  ✗ vitest.config.ts — should be skipped for a Jest project"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$JTMP"

# (T) pytest.ini is NOT shipped when pyproject.toml already configures pytest.
PTMP=$(mktemp -d)
( cd "$PTMP" && git init --quiet \
  && printf '[tool.pytest.ini_options]\naddopts = "-q"\n' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify ) >"$HOOK_OUT" 2>&1
if [ ! -f "$PTMP/pytest.ini" ] && grep -q "pytest config exists" "$HOOK_OUT"; then
  echo "  ✓ pytest.ini skipped when pyproject configures pytest"; PASS=$((PASS + 1))
else
  echo "  ✗ pytest.ini — should be skipped when pyproject has [tool.pytest.ini_options]"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$PTMP"
reset_repo

# --- install never clobbers user-owned files (CLAUDE.md / AGENTS.md) --------
# Regression guard for the reported data-loss bug: install.sh --force used to
# overwrite a hand-written CLAUDE.md wholesale with the pointer stub. CLAUDE.md
# is now merged (import block appended once) and AGENTS.md is never replaced.
# shellcheck disable=SC2164
cd "$WORK"
mk_userproj() {
  local d; d=$(mktemp -d)
  ( cd "$d" && git init --quiet && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml \
    && printf '# Mine\n\nHAND-WRITTEN-MEMORY\n' >CLAUDE.md \
    && printf '# AGENTS\n\nCUSTOM-PROJECT-SECTION\n' >AGENTS.md )
  echo "$d"
}

# (T) install merges CLAUDE.md: keeps user content AND appends the import.
UMG=$(mk_userproj)
( cd "$UMG" && "$SCAFFOLD_DIR/install.sh" --both --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'HAND-WRITTEN-MEMORY' "$UMG/CLAUDE.md" && grep -q '@AGENTS.md' "$UMG/CLAUDE.md"; then
  echo "  ✓ install merges CLAUDE.md (keeps content + adds import)"; PASS=$((PASS + 1))
else
  echo "  ✗ install should merge CLAUDE.md, not replace it"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UMG"

# (T) install --force must NOT clobber CLAUDE.md or a customized AGENTS.md.
UFC=$(mk_userproj)
( cd "$UFC" && "$SCAFFOLD_DIR/install.sh" --both --force --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'HAND-WRITTEN-MEMORY' "$UFC/CLAUDE.md" && grep -q 'CUSTOM-PROJECT-SECTION' "$UFC/AGENTS.md"; then
  echo "  ✓ --force preserves user CLAUDE.md and AGENTS.md"; PASS=$((PASS + 1))
else
  echo "  ✗ --force clobbered a user-owned file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UFC"

# (T) install is idempotent — CLAUDE.md import block appears exactly once.
UIDEM=$(mk_userproj)
( cd "$UIDEM" && "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null 2>&1 \
             && "$SCAFFOLD_DIR/install.sh" --both --no-verify ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:begin' "$UIDEM/CLAUDE.md")" = "1" ]; then
  echo "  ✓ CLAUDE.md import is idempotent (appended once)"; PASS=$((PASS + 1))
else
  echo "  ✗ CLAUDE.md import not idempotent"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UIDEM"

# (T) --force backs up a locally-modified scaffold file before replacing it.
UBK=$(mk_userproj)
( cd "$UBK" && "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null 2>&1 \
            && echo '# local edit' >>ruff.toml \
            && "$SCAFFOLD_DIR/install.sh" --both --force --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$UBK/ruff.toml.scaffold-bak" ] && grep -q 'local edit' "$UBK/ruff.toml.scaffold-bak"; then
  echo "  ✓ --force backs up changed files to .scaffold-bak"; PASS=$((PASS + 1))
else
  echo "  ✗ --force did not back up the changed file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UBK"

# (T) uninstall strips the scaffold block but keeps the user's CLAUDE.md content.
UUN=$(mk_userproj)
( cd "$UUN" && "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null 2>&1 \
            && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if grep -q 'HAND-WRITTEN-MEMORY' "$UUN/CLAUDE.md" && ! grep -q 'ai-coding-rules-scaffold:begin' "$UUN/CLAUDE.md"; then
  echo "  ✓ uninstall strips block, keeps CLAUDE.md content"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall should strip only the block, keep content"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UUN"

# (T) uninstall data-loss regression: a begin marker WITHOUT an end marker (the
# user edited the block away, or a prior install was interrupted) must leave the
# file untouched. The old open-ended `/begin/,/end/d` deleted to EOF and ate
# everything below the lone begin marker — the exact data-loss class guarded.
UBE=$(mktemp -d)
( cd "$UBE" && git init --quiet \
  && printf '<!-- ai-coding-rules-scaffold:begin -->\n@AGENTS.md\nMY IMPORTANT NOTES\n' >CLAUDE.md \
  && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if grep -q 'MY IMPORTANT NOTES' "$UBE/CLAUDE.md"; then
  echo "  ✓ uninstall leaves begin-without-end CLAUDE.md untouched (no EOF eat)"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall ate content below a lone begin marker"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UBE"

# (T) well-formed block strip: a proper begin..end block is removed, the user's
# content above AND below survives, and no begin/end marker residue remains.
UWF=$(mktemp -d)
( cd "$UWF" && git init --quiet \
  && printf '# Mine\n<!-- ai-coding-rules-scaffold:begin -->\n@AGENTS.md\n<!-- ai-coding-rules-scaffold:end -->\nAFTER THE BLOCK\n' >CLAUDE.md \
  && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if grep -q '# Mine' "$UWF/CLAUDE.md" && grep -q 'AFTER THE BLOCK' "$UWF/CLAUDE.md" \
   && ! grep -q 'ai-coding-rules-scaffold:begin' "$UWF/CLAUDE.md" \
   && ! grep -q 'ai-coding-rules-scaffold:end' "$UWF/CLAUDE.md"; then
  echo "  ✓ uninstall strips a well-formed block, keeps content above + below"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall should strip the block and keep surrounding content"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UWF"

# (T) no-trailing-newline append (A3): when the pre-existing CLAUDE.md ends
# without a final newline, install must still place its import block on its own
# line — not concatenate `HANDWRITTEN-LAST-LINE<!-- ...begin -->` onto one line.
UNL=$(mktemp -d)
( cd "$UNL" && git init --quiet && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml \
  && printf '# Mine\n\nHANDWRITTEN-LAST-LINE' >CLAUDE.md \
  && "$SCAFFOLD_DIR/install.sh" --both --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'HANDWRITTEN-LAST-LINE' "$UNL/CLAUDE.md" \
   && ! grep -q 'HANDWRITTEN-LAST-LINE.*ai-coding-rules-scaffold:begin' "$UNL/CLAUDE.md"; then
  echo "  ✓ install appends import on a new line (no-trailing-newline file)"; PASS=$((PASS + 1))
else
  echo "  ✗ install concatenated the import onto the last handwritten line"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UNL"

# --- installer does not write THROUGH a symlink at a scaffold path (A7) -------
# A pre-existing symlink at a scaffold destination used to make cp follow it and
# write the scanner to the link's target OUTSIDE the repo, leaving the installed
# scanner as a symlink (arbitrary write + scanner substitution).

# (T) live symlink -> outside file, with --force: the outside file must NOT be
#     overwritten, and the installed path must become a real regular file.
USL=$(mktemp -d)
mkdir -p "$USL/repo/.githooks/lib"
printf 'PRECIOUS_DO_NOT_TOUCH\n' >"$USL/outside_target"
ln -s "$USL/outside_target" "$USL/repo/.githooks/lib/check-secrets"
( cd "$USL/repo" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --force --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$USL/repo/.githooks/lib/check-secrets" ] && [ ! -L "$USL/repo/.githooks/lib/check-secrets" ] \
   && grep -q 'PRECIOUS_DO_NOT_TOUCH' "$USL/outside_target" \
   && head -1 "$USL/repo/.githooks/lib/check-secrets" | grep -q '#!/usr/bin/env bash'; then
  echo "  ✓ install replaces a symlinked scaffold path with a real file (no write-through)"; PASS=$((PASS + 1))
else
  echo "  ✗ install wrote through a symlink or clobbered the outside target"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USL"

# (T) DANGLING symlink -> outside path, no --force: must be skipped, NOT written
#     through (the dangling case is where `[ -e ]` is false and cp used to fall
#     through and create the outside file).
USD=$(mktemp -d)
mkdir -p "$USD/repo/.githooks/lib"
ln -s "$USD/nonexistent_outside" "$USD/repo/.githooks/lib/check-filenames"
( cd "$USD/repo" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ ! -e "$USD/nonexistent_outside" ]; then
  echo "  ✓ install does not write through a dangling symlink (no --force)"; PASS=$((PASS + 1))
else
  echo "  ✗ install wrote through a dangling symlink to an outside path"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USD"

# (T) uninstall removes ci-changed-files too (install adds 8 libs; the uninstall
#     loop dropped this one, leaving the scaffold half-uninstalled).
UCI=$(mktemp -d)
( cd "$UCI" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 \
  && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$UCI/.githooks/lib/ci-changed-files" ]; then
  echo "  ✓ uninstall removes .githooks/lib/ci-changed-files"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall left ci-changed-files behind"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UCI"
reset_repo

# --- installer upgrade story: re-runs refresh scaffold-owned code -------------
# A plain re-run must REFRESH scaffold-owned code (check-*, libs, hooks,
# workflows) so security fixes reach an upgrader who just re-runs install.sh,
# LEAVE user-owned files alone, and NOTIFY (never silently overwrite) on
# .forbidden-patterns/*.txt drift. Each upgrade scenario installs once, mutates
# one file to simulate the prior state, then re-runs and asserts the outcome.

# (T) re-run refreshes a STALE scaffold-owned scanner to the shipped version,
#     without --force — the core upgrade path the design note called for.
#     Simulate an older installed scanner by clobbering it, then re-run and
#     assert it matches the template again, is announced as updated, and stays
#     executable (the post-copy chmod must still run on the refreshed file).
URS=$(mktemp -d)
( cd "$URS" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\n# STALE OLD VERSION\nexit 0\n' >"$URS/.githooks/lib/check-secrets"
( cd "$URS" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if cmp -s "$SCAFFOLD_DIR/githooks/lib/check-secrets.template" "$URS/.githooks/lib/check-secrets" \
   && [ -x "$URS/.githooks/lib/check-secrets" ] \
   && grep -q 'updated:.*check-secrets' "$HOOK_OUT"; then
  echo "  ✓ re-run refreshes a stale scaffold-owned scanner to the shipped version"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run did not refresh the stale scanner"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$URS"

# (T) re-run refreshes a stale scaffold-owned WORKFLOW (lint.yml) too — the
#     guardrails job hardening has to reach upgraders, not just the scanners.
URW=$(mktemp -d)
( cd "$URW" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
echo '# stale workflow' >"$URW/.github/workflows/lint.yml"
( cd "$URW" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if cmp -s "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" "$URW/.github/workflows/lint.yml" \
   && grep -q 'updated:.*lint.yml' "$HOOK_OUT"; then
  echo "  ✓ re-run refreshes a stale scaffold-owned workflow"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run did not refresh the stale workflow"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$URW"

# (T) re-run LEAVES a user-edited, user-owned config alone — no refresh, no
#     backup. The scaffold-owned auto-update must not bleed into user files.
UUE=$(mktemp -d)
( cd "$UUE" && git init --quiet && echo 'name="x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify >/dev/null 2>&1 )
echo '# my local ruff tweak' >>"$UUE/ruff.toml"
( cd "$UUE" && "$SCAFFOLD_DIR/install.sh" --python --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'my local ruff tweak' "$UUE/ruff.toml" \
   && grep -q 'skip (exists): ruff.toml' "$HOOK_OUT" \
   && [ ! -e "$UUE/ruff.toml.scaffold-bak" ]; then
  echo "  ✓ re-run leaves a user-edited config untouched (no refresh, no backup)"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run should leave a user-owned config alone"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UUE"

# (T) re-run NOTIFIES on .forbidden-patterns drift and KEEPS the user's custom
#     rules — these files are scaffold-shipped AND user-extended, so a silent
#     overwrite would clobber a team's added rows. Notify, never overwrite.
UPD=$(mktemp -d)
( cd "$UPD" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
printf '\nMYCUSTOMRULE\tmy custom rule\n' >>"$UPD/.forbidden-patterns/secrets.txt"
( cd "$UPD" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'MYCUSTOMRULE' "$UPD/.forbidden-patterns/secrets.txt" \
   && grep -q 'note (drift)' "$HOOK_OUT" && grep -q 'secrets.txt' "$HOOK_OUT"; then
  echo "  ✓ re-run notifies on forbidden-patterns drift, keeps user rules"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run should notify (not overwrite) on pattern drift"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UPD"

# (T) --force on a drifted pattern file backs up the user's version, then
#     installs the shipped one (the user's rows land in .scaffold-bak to merge
#     back) — the documented escape hatch from the drift note.
UPF=$(mktemp -d)
( cd "$UPF" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
printf '\nMYCUSTOMRULE\tmy custom rule\n' >>"$UPF/.forbidden-patterns/secrets.txt"
( cd "$UPF" && "$SCAFFOLD_DIR/install.sh" --frontend --force --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$UPF/.forbidden-patterns/secrets.txt.scaffold-bak" ] \
   && grep -q 'MYCUSTOMRULE' "$UPF/.forbidden-patterns/secrets.txt.scaffold-bak" \
   && cmp -s "$SCAFFOLD_DIR/forbidden-patterns/secrets.txt.template" "$UPF/.forbidden-patterns/secrets.txt"; then
  echo "  ✓ --force backs up a drifted pattern file then installs the shipped one"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should back up then replace a drifted pattern file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UPF"

# (T) a re-run over an already-current install is a CLEAN no-op: scaffold-owned
#     files match the shipped version, so nothing is refreshed and no drift
#     note fires. Guards against spurious churn / .scaffold-bak clutter on every
#     routine re-run.
UNO=$(mktemp -d)
( cd "$UNO" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
( cd "$UNO" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if ! grep -q 'updated:' "$HOOK_OUT" && ! grep -q 'note (drift)' "$HOOK_OUT"; then
  echo "  ✓ re-run over a current install is a clean no-op"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run churned an already-current install"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UNO"
reset_repo
