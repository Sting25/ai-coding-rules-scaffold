# shellcheck shell=bash
# cases/51-mutation-diff-config.sh: the mutmut config check-mutation-diff builds
# and how it reports a failing baseline, plus the base test-guard hands it
# (#197, #198, #199). Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/
# SCAFFOLD_DIR are in scope. Helpers are prefixed md_.
#   #197  the generated [tool.mutmut] table dropped the project's also_copy and
#         pointed source_paths at each changed file's leaf directory, so
#         mutants/ held a truncated package.
#   #198  mutmut's "Failed to run clean test" (test state leaking between its
#         in-process pytest.main calls) fell through to the advisory path.
#   #199  hard failures printed a canned line and discarded mutmut's output;
#         test-guard diffed from the stale pull_request.base.sha.
#   review fixes: namespace-package roots, TOML-safe carry (no tables), the
#         "no trampoline hit matches a mutant" hard failure, and a base derived
#         with merge-base only (a HEAD^2 test mistakes a PR head that merged
#         its base for the synthetic merge).
# mutmut itself is not installed here: a stub package stands in for it, which
# is enough because every assertion is about what this script writes and says.

echo "cases/51: check-mutation-diff config and failure reporting, test-guard base (#197, #198, #199)"

MD_TPL="$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template"
MD_WF="$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template"
MD=$(mktemp -d)
md_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# --- (A) inject_config: also_copy carried, source_paths is the package root --------
mkdir -p "$MD/wt/app/features/admin" "$MD/wt/scripts" "$MD/wt/src/pkg/sub" "$MD/wt/ns/features/admin"
touch "$MD/wt/app/__init__.py" "$MD/wt/app/features/__init__.py" "$MD/wt/app/features/admin/__init__.py" \
      "$MD/wt/src/pkg/__init__.py" "$MD/wt/src/pkg/sub/__init__.py"
cat >"$MD/wt/pyproject.toml" <<'EOF'
[project]
name = "demo"

[tool.mutmut]
source_paths = ["old"]
also_copy = [
    "deploy/",
    "static/",
]
pytest_add_cli_args_test_selection = ["tests/"]
do_not_mutate = ["*/migrations/*"]

[tool.other]
keep = true
EOF
cat >"$MD/inject.py" <<'EOF'
import importlib.machinery, importlib.util, os, sys
if os.environ.get("MD_NO_TOMLLIB"):
    sys.modules["tomllib"] = None  # `import tomllib` now raises ImportError: the pre-3.11 path
loader = importlib.machinery.SourceFileLoader("cmd", sys.argv[1])
spec = importlib.util.spec_from_loader("cmd", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
dirs, _ = mod.inject_config(sys.argv[2], sys.argv[3:])
print("DIRS=" + ",".join(dirs))
EOF
md_files="app/features/admin/x.py app/y.py scripts/tool.py src/pkg/sub/z.py ns/features/admin/n.py"
# The pre-3.11 path (no tomllib) is forced on whatever python3 this is, so it is
# exercised on every machine; the tomllib path runs in (A2) below.
# shellcheck disable=SC2086  # md_files is a deliberate word list
MD_NO_TOMLLIB=1 python3 "$MD/inject.py" "$MD_TPL" "$MD/wt" $md_files >"$HOOK_OUT" 2>&1
md_toml=$(cat "$MD/wt/pyproject.toml")
if grep -qx 'DIRS=app,ns,scripts,src/pkg' "$HOOK_OUT"; then
  echo "  ✓ source_paths is the package root of each changed file, de-duplicated: the highest __init__.py ancestor (app, src/pkg), the top of a namespace layout with no __init__.py (ns), a script keeps its directory"; PASS=$((PASS + 1))
else
  echo "  ✗ expected source_paths app,ns,scripts,src/pkg"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# Whitespace-stripped, so a multi-line array (verbatim on this path) and a one-line
# one (re-emitted on the tomllib path) both match.
md_flat=$(printf '%s' "$md_toml" | tr -d ' \n')
if printf '%s' "$md_flat" | grep -qE 'also_copy=\["deploy/","static/",?\]' \
   && printf '%s' "$md_flat" | grep -qF 'pytest_add_cli_args_test_selection=["tests/"]' \
   && [ "$(printf '%s\n' "$md_toml" | grep -c '^source_paths')" -eq 1 ] \
   && ! printf '%s\n' "$md_toml" | grep -qF '"old"'; then
  echo "  ✓ (no tomllib) the project's also_copy and test selection are carried; its own source_paths is replaced"; PASS=$((PASS + 1))
else
  echo "  ✗ expected also_copy and test selection carried, source_paths replaced"; printf '%s\n' "$md_toml" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi
# (A2) the tomllib path: every other key, TOML-safe. Needs Python 3.11+, so the
# interpreter is searched for; with none, the skip is printed and counted (the
# driver's floor counts PASS + SKIP), never silent.
md_py=""
for md_c in python3.13 python3.12 python3.11 python3; do
  if command -v "$md_c" >/dev/null 2>&1 && "$md_c" -c 'import tomllib' 2>/dev/null; then md_py="$md_c"; break; fi
done
if [ -n "$md_py" ]; then
  mkdir -p "$MD/wt/lib/ns2/feat"
  cat >"$MD/wt/pyproject.toml" <<'EOF'
[tool.setuptools.packages.find]
where = ["lib"]

[tool.mutmut]
source_paths = ["old"]
also_copy = ["deploy/"]
do_not_mutate = ["*/migrations/*"]
max_stack_depth = 5
debug = true
extra = { a = 1 }

[tool.mutmut.nested]
x = 1

[tool.other]
keep = true
EOF
  "$md_py" "$MD/inject.py" "$MD_TPL" "$MD/wt" app/y.py lib/ns2/feat/q.py >"$HOOK_OUT" 2>&1
  if grep -qx 'do_not_mutate = \["\*/migrations/\*"\]' "$MD/wt/pyproject.toml" \
     && grep -qx 'also_copy = \["deploy/"\]' "$MD/wt/pyproject.toml" \
     && grep -qx 'keep = true' "$MD/wt/pyproject.toml" \
     && "$md_py" -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$MD/wt/pyproject.toml"; then
    echo "  ✓ ($md_py) every other [tool.mutmut] key is carried and the result still parses as TOML"; PASS=$((PASS + 1))
  else
    echo "  ✗ ($md_py) expected do_not_mutate and also_copy carried over"; sed 's/^/      /' "$MD/wt/pyproject.toml"; FAIL=$((FAIL + 1))
  fi
  if grep -qx 'max_stack_depth = 5' "$MD/wt/pyproject.toml" && grep -qx 'debug = true' "$MD/wt/pyproject.toml" \
     && ! grep -qE '^(extra|nested|x) ' "$MD/wt/pyproject.toml" \
     && [ "$(grep -c '^\[tool\.mutmut' "$MD/wt/pyproject.toml")" -eq 1 ] \
     && grep -qF 'extra is a table' "$HOOK_OUT" && grep -qF 'nested is a table' "$HOOK_OUT"; then
    echo "  ✓ ($md_py) numbers and booleans carry; a table-valued key and a [tool.mutmut.nested] subtable are dropped with a stderr note, not emitted as invalid or duplicate TOML"; PASS=$((PASS + 1))
  else
    echo "  ✗ ($md_py) expected scalars carried and the table-valued key and subtable dropped with a note"; sed 's/^/      /' "$MD/wt/pyproject.toml" "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  if grep -qx 'DIRS=app,lib/ns2' "$HOOK_OUT"; then
    echo "  ✓ ($md_py) a namespace layout under a declared source root (packages.find.where = lib) is rooted below it (lib/ns2)"; PASS=$((PASS + 1))
  else
    echo "  ✗ ($md_py) expected source_paths app, lib/ns2"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  - SKIP: no python3.11+ (tomllib) found — 3 assertions (key carry, table drop, declared source roots) did NOT run; install Python 3.11+ to cover the tomllib path"
  SKIP=$((SKIP + 3))
fi

# --- (B) hard failures: explanation, mutmut output, and no retry ---------------------
# A stub mutmut that prints $MD_STUB_OUT and counts its invocations. importlib.metadata
# finds its dist-info through PYTHONPATH, so verify_mutmut() accepts it as 3.7.0.
mkdir -p "$MD/stub/mutmut" "$MD/stub/mutmut-3.7.0.dist-info"
printf 'Metadata-Version: 2.1\nName: mutmut\nVersion: 3.7.0\n' >"$MD/stub/mutmut-3.7.0.dist-info/METADATA"
: >"$MD/stub/mutmut/__init__.py"
cat >"$MD/stub/mutmut/__main__.py" <<'EOF'
import os, sys
with open(os.environ["MD_STUB_COUNT"], "a") as f:
    f.write("run\n")
sys.stdout.write(open(os.environ["MD_STUB_OUT"]).read())
sys.exit(1)
EOF
git init -q "$MD/repo"
mkdir -p "$MD/repo/app"
: >"$MD/repo/app/__init__.py"
printf 'def f():\n    return 1\n' >"$MD/repo/app/m.py"
md_git "$MD/repo" add -A && md_git "$MD/repo" commit -q -m base
printf 'def f():\n    return 2\n' >"$MD/repo/app/m.py"
md_git "$MD/repo" commit -q -am change

md_run() {  # $1 = text mutmut ends with; sets md_rc, output in $HOOK_OUT
  { for i in $(seq 1 60); do echo "mutmut noise line $i"; done; echo "$1"; } >"$MD/stub.out"
  : >"$MD/count"
  md_rc=0
  ( cd "$MD/repo" && MD_STUB_OUT="$MD/stub.out" MD_STUB_COUNT="$MD/count" PYTHONPATH="$MD/stub" \
      python3 "$MD_TPL" --base HEAD~1 ) >"$HOOK_OUT" 2>&1 || md_rc=$?
}

md_run "Failed to run clean test"
if [ "$md_rc" -eq 2 ] && grep -qF 'Failed to run clean test' "$HOOK_OUT" \
   && grep -qF 'in-process pytest runs' "$HOOK_OUT" && grep -qF 'did not select' "$HOOK_OUT" \
   && grep -qF 'belongs in the suite' "$HOOK_OUT" && ! grep -q 'not checked' "$HOOK_OUT"; then
  echo "  ✓ \"Failed to run clean test\" exits 2 and names both causes (state leak, a test relying on an unselected one), not the advisory path"; PASS=$((PASS + 1))
else
  echo "  ✗ expected exit 2 with the two-cause explanation (got exit $md_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
if [ "$(wc -l <"$MD/count" | tr -d ' ')" -eq 1 ]; then
  echo "  ✓ mutmut ran exactly once: that failure is not retried"; PASS=$((PASS + 1))
else
  echo "  ✗ mutmut must run exactly once on that failure (ran $(wc -l <"$MD/count" | tr -d ' ') times)"; FAIL=$((FAIL + 1))
fi
if grep -qF 'mutmut noise line 60' "$HOOK_OUT" && grep -qF 'mutmut noise line 22' "$HOOK_OUT" \
   && ! grep -qF 'mutmut noise line 21' "$HOOK_OUT"; then
  echo "  ✓ the last 40 lines of mutmut's output are printed on the hard-failure path, and no more"; PASS=$((PASS + 1))
else
  echo "  ✗ expected exactly the last 40 lines of mutmut output (lines 22 to 60 plus the final message)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
md_run "mutmut: failed to collect stats"
if [ "$md_rc" -eq 2 ] && grep -qF 'baseline test suite fails' "$HOOK_OUT" && grep -qF 'mutmut noise line 60' "$HOOK_OUT"; then
  echo "  ✓ \"failed to collect stats\" also prints mutmut's output"; PASS=$((PASS + 1))
else
  echo "  ✗ expected exit 2 with mutmut's output after the stats failure (got exit $md_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
md_run "Stopping early, because tests recorded trampoline hits but none match any mutant key"
if [ "$md_rc" -eq 2 ] && grep -qF 'none match any mutant key' "$HOOK_OUT" && grep -qF 'other than the mutants/ copy' "$HOOK_OUT"; then
  echo "  ✓ \"tests recorded trampoline hits but none match any mutant key\" exits 2 with an explanation, not an all-not-checked green"; PASS=$((PASS + 1))
else
  echo "  ✗ expected exit 2 and the trampoline explanation (got exit $md_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# --- (C) test-guard: one derived base, shared by red-green and mutation ---------------
# The base is resolved once, by the "Resolve base commit" step; its run block is lifted
# so this tests the text consumers get, with GITHUB_OUTPUT pointed at a file.
md_blk=$(awk '/- name: Resolve base commit/ { on = 1 } on && /^ +run: \|/ { inb = 1; next }
  inb && /^ {10}/ { sub(/^ {10}/, ""); print; next } inb && /^[ ]*$/ { next } inb { exit }' "$MD_WF")
md_active=$(grep -v '^ *#' "$MD_WF")
# shellcheck disable=SC2016  # ${{ }} is literal workflow text in the grep pattern
if ! printf '%s\n' "$md_active" | grep -q 'pull_request\.base\.sha' \
   && ! printf '%s\n' "$md_active" | grep -q 'HEAD^2' \
   && [ "$(printf '%s\n' "$md_active" | grep -c 'BASE_SHA: \${{ steps\.base\.outputs\.sha }}')" -eq 2 ] \
   && printf '%s\n' "$md_blk" | grep -q 'git merge-base'; then
  echo "  ✓ test-guard.yml.template: no stale pull_request.base.sha and no HEAD^2 test; red-green and mutation both read the one resolved base"; PASS=$((PASS + 1))
else
  echo "  ✗ test-guard.yml.template: expected one merge-base step feeding both checks (no pull_request.base.sha, no HEAD^2)"; FAIL=$((FAIL + 1))
fi
md_base() {  # $1 = GITHUB_BASE_REF; prints the resolved sha, rc 1 and stderr in $HOOK_OUT when none
  : >"$MD/gh_out"
  ( cd "$MD/pr" && GITHUB_BASE_REF="$1" GITHUB_OUTPUT="$MD/gh_out" bash -e -c "$md_blk" ) >"$HOOK_OUT" 2>&1 || return 1
  sed -n 's/^sha=//p' "$MD/gh_out"
}
# main moves on (c2) after the PR branched (c1); the synthetic PR merge has c2 as first parent.
git init -q "$MD/pr" && md_git "$MD/pr" commit -q --allow-empty -m c1 && md_git "$MD/pr" branch -M main
md_c1=$(git -C "$MD/pr" rev-parse HEAD)
md_git "$MD/pr" checkout -q -b feature && md_git "$MD/pr" commit -q --allow-empty -m p1
md_git "$MD/pr" checkout -q main && md_git "$MD/pr" commit -q --allow-empty -m c2
md_c2=$(git -C "$MD/pr" rev-parse HEAD)
git -C "$MD/pr" update-ref refs/remotes/origin/main "$md_c2"
md_git "$MD/pr" checkout -q --detach && md_git "$MD/pr" merge -q --no-ff -m merge feature
md_got=$(md_base main) || md_got=""
if [ "$md_got" = "$md_c2" ] && [ "$md_got" != "$md_c1" ]; then
  echo "  ✓ PR merge checkout: the base is its first parent, the current base tip, not the older commit the PR branched from"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the first parent ($md_c2) on a merge checkout, got '$md_got'"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# A checkout of the PR head itself: the base is where the PR left main.
md_git "$MD/pr" checkout -q --detach feature
md_got=$(md_base main) || md_got=""
if [ "$md_got" = "$md_c1" ]; then
  echo "  ✓ PR head checkout: the base is the merge-base with origin/\$GITHUB_BASE_REF"; PASS=$((PASS + 1))
else
  echo "  ✗ expected merge-base ($md_c1) on a PR head checkout, got '$md_got'"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# A PR head that is itself a merge commit (it merged main): HEAD^2 exists here but is not
# GitHub's synthetic merge, and HEAD^1 would drop the PR's own work from the diff.
md_git "$MD/pr" checkout -q -b feature2 feature && md_git "$MD/pr" merge -q --no-ff -m "merge main" main
md_p1=$(git -C "$MD/pr" rev-parse HEAD^1)
md_got=$(md_base main) || md_got=""
if [ "$md_got" = "$md_c2" ] && [ "$md_got" != "$md_p1" ]; then
  echo "  ✓ PR head that merged its base: the base is the merge-base (the base tip), not HEAD^1, so the PR's own files stay in the diff"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the base tip ($md_c2) on a PR head that merged main, got '$md_got'"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
md_got=$(md_base no-such-branch) && md_rc=0 || md_rc=$?
if [ "$md_rc" -ne 0 ] && [ -z "$md_got" ] && grep -qF '::error::cannot resolve origin/no-such-branch' "$HOOK_OUT"; then
  echo "  ✓ an unresolvable origin/\$GITHUB_BASE_REF fails the step with a clear message"; PASS=$((PASS + 1))
else
  echo "  ✗ expected a failing step and a named error for an unknown base branch (rc $md_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

rm -rf "$MD"
