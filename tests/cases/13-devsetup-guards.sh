# shellcheck shell=bash
# cases/13-devsetup-guards.sh — scripts/dev-setup.sh symlink write-through (B4)
# and core.hooksPath wiring guards (B9/B10). Split out of cases/09 to keep both
# files under the scaffold's own 500-line module cap. Sourced into the driver's
# shell (uses $SCAFFOLD_DIR, $WORK, $HOOK_OUT, PASS/FAIL, reset_repo from common).
# shellcheck disable=SC2164
cd "$WORK"

# --- dev-setup.sh does not write THROUGH a symlink at a rendered path (B4) -----
# scripts/dev-setup.sh renders templates into the gitignored .githooks/ /
# .forbidden-patterns/ for the scaffold's OWN dogfooding. It used bare `cp` /
# `mkdir -p`, so a leftover/planted symlink there (surviving across checkouts,
# since those dirs are gitignored) made cp write a scanner THROUGH the link to an
# outside target, or mkdir -p follow a symlinked lib/ dir — the A7 class install.sh
# already defends. dev-setup refuses to run outside a scaffold clone, so build a
# MINIMAL fake clone (it resolves its root from its own path) and drive it.
_b4_fakeclone() {   # $1 = dir to build a minimal runnable dev-setup clone into
  local d=$1
  mkdir -p "$d/scripts" "$d/githooks/lib" "$d/forbidden-patterns"
  cp "$SCAFFOLD_DIR/scripts/dev-setup.sh" "$d/scripts/dev-setup.sh"
  printf '#!/usr/bin/env bash\n' >"$d/githooks/pre-commit.template"
  printf '#!/usr/bin/env bash\n' >"$d/githooks/commit-msg.template"
  printf '#!/usr/bin/env bash\n# scanner\n' >"$d/githooks/lib/check-secrets.template"
  printf 'pat\tdesc\n' >"$d/forbidden-patterns/secrets.txt.template"
  ( cd "$d" && git init --quiet && git config user.email t@t.local && git config user.name t )
}

# (T) file symlink at a rendered scanner path -> outside victim: the victim must
#     NOT be overwritten, and the rendered path must become a real regular file.
BF=$(mktemp -d)
_b4_fakeclone "$BF/clone"
printf 'PRECIOUS_DO_NOT_TOUCH\n' >"$BF/outside_target"
mkdir -p "$BF/clone/.githooks/lib"
ln -s "$BF/outside_target" "$BF/clone/.githooks/lib/check-secrets"
( cd "$BF/clone" && bash scripts/dev-setup.sh ) >"$HOOK_OUT" 2>&1 || true
if grep -q 'PRECIOUS_DO_NOT_TOUCH' "$BF/outside_target" \
   && [ -f "$BF/clone/.githooks/lib/check-secrets" ] && [ ! -L "$BF/clone/.githooks/lib/check-secrets" ]; then
  echo "  ✓ dev-setup replaces a symlinked rendered path with a real file (no write-through)"; PASS=$((PASS + 1))
else
  echo "  ✗ dev-setup wrote through a symlink or clobbered the outside target (B4)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$BF"

# (T) symlinked .githooks/lib DIR -> outside dir: mkdir -p must NOT follow it, so
#     no scanner lands outside the repo and the rendered lib/ is a real dir.
BD=$(mktemp -d)
_b4_fakeclone "$BD/clone"
mkdir -p "$BD/clone/.githooks" "$BD/outside_dir"
ln -s "$BD/outside_dir" "$BD/clone/.githooks/lib"
( cd "$BD/clone" && bash scripts/dev-setup.sh ) >"$HOOK_OUT" 2>&1 || true
if [ ! -e "$BD/outside_dir/check-secrets" ] \
   && [ -d "$BD/clone/.githooks/lib" ] && [ ! -L "$BD/clone/.githooks/lib" ]; then
  echo "  ✓ dev-setup does not render through a symlinked lib/ dir (no outside write)"; PASS=$((PASS + 1))
else
  echo "  ✗ dev-setup followed a symlinked lib/ dir and wrote a scanner outside the repo (B4)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$BD"

# --- dev-setup.sh guards the core.hooksPath wiring like install.sh (B9 / B10) --
# install.sh:403-414 guards the `git config core.hooksPath` step two ways;
# dev-setup.sh ran it unconditionally. Reuse the minimal fake clone (dev-setup
# resolves its root from its own path, so a scripts/ + templates tree is enough).

# (T) B10 — a pre-existing core.hooksPath (Husky/lefthook) must be PRESERVED, not
#     silently clobbered to .githooks. Reverting the guard sets it to .githooks
#     (this case turns red), mutation-proving the preserve arm.
HP=$(mktemp -d)
_b4_fakeclone "$HP/clone"
( cd "$HP/clone" && git config core.hooksPath .husky )
( cd "$HP/clone" && bash scripts/dev-setup.sh ) >"$HOOK_OUT" 2>&1 || true
if [ "$( cd "$HP/clone" && git config --get core.hooksPath )" = ".husky" ] \
   && grep -qi "already '.husky'" "$HOOK_OUT"; then
  echo "  ✓ dev-setup preserves a pre-existing core.hooksPath (no Husky clobber)"; PASS=$((PASS + 1))
else
  echo "  ✗ dev-setup clobbered a pre-existing core.hooksPath (B10)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$HP"

# (T) B10 happy path — with NO pre-existing hooksPath, dev-setup still sets
#     .githooks (guards the fix from breaking the normal dogfooding wiring).
HH=$(mktemp -d)
_b4_fakeclone "$HH/clone"
( cd "$HH/clone" && bash scripts/dev-setup.sh ) >"$HOOK_OUT" 2>&1 || true
if [ "$( cd "$HH/clone" && git config --get core.hooksPath )" = ".githooks" ]; then
  echo "  ✓ dev-setup sets core.hooksPath -> .githooks when unset (happy path)"; PASS=$((PASS + 1))
else
  echo "  ✗ dev-setup did not wire core.hooksPath on a fresh clone (B10 regression)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$HH"

# (T) B9 — run before `git init` (a non-git checkout / tarball): dev-setup must
#     WARN and exit 0, not abort with a raw `fatal: not in a git directory`
#     (exit 128) after every file is already rendered. Build the fake clone WITHOUT
#     `git init`; mktemp dirs are not inside a repo, so the git-dir guard fires.
#     Reverting the guard makes the run exit 128 (this case turns red).
NG=$(mktemp -d)
mkdir -p "$NG/clone/scripts" "$NG/clone/githooks/lib" "$NG/clone/forbidden-patterns"
cp "$SCAFFOLD_DIR/scripts/dev-setup.sh" "$NG/clone/scripts/dev-setup.sh"
printf '#!/usr/bin/env bash\n' >"$NG/clone/githooks/pre-commit.template"
printf '#!/usr/bin/env bash\n' >"$NG/clone/githooks/commit-msg.template"
printf '#!/usr/bin/env bash\n# scanner\n' >"$NG/clone/githooks/lib/check-secrets.template"
printf 'pat\tdesc\n' >"$NG/clone/forbidden-patterns/secrets.txt.template"
if ( cd "$NG/clone" && bash scripts/dev-setup.sh ) >"$HOOK_OUT" 2>&1 \
   && grep -qi 'not in a git repo' "$HOOK_OUT"; then
  echo "  ✓ dev-setup warns + exits 0 when run before git init (no exit 128)"; PASS=$((PASS + 1))
else
  echo "  ✗ dev-setup aborted instead of warning without a git dir (B9)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$NG"
reset_repo
