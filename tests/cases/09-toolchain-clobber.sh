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
reset_repo
