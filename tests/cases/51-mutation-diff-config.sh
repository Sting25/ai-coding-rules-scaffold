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
# mutmut itself is not installed here: a stub package stands in for it, which
# is enough because every assertion is about what this script writes and says.

echo "cases/51: check-mutation-diff config and failure reporting, test-guard base (#197, #198, #199)"

MD_TPL="$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template"
MD_WF="$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template"
MD=$(mktemp -d)
md_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# --- (A) inject_config: also_copy carried, source_paths is the package root --------
mkdir -p "$MD/wt/app/features/admin" "$MD/wt/scripts" "$MD/wt/src/pkg/sub"
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
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("cmd", sys.argv[1])
spec = importlib.util.spec_from_loader("cmd", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
dirs, _ = mod.inject_config(sys.argv[2], sys.argv[3:])
print("DIRS=" + ",".join(dirs))
EOF
md_files="app/features/admin/x.py app/y.py scripts/tool.py src/pkg/sub/z.py"
# shellcheck disable=SC2086  # md_files is a deliberate word list
python3 "$MD/inject.py" "$MD_TPL" "$MD/wt" $md_files >"$HOOK_OUT" 2>&1
md_toml=$(cat "$MD/wt/pyproject.toml")
if grep -qx 'DIRS=app,scripts,src/pkg' "$HOOK_OUT"; then
  echo "  ✓ source_paths is the top-level package root of each changed file, de-duplicated (app, src/pkg), a script keeps its directory"; PASS=$((PASS + 1))
else
  echo "  ✗ expected source_paths app,scripts,src/pkg"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# Whitespace-stripped, so a multi-line array (verbatim on this path) and a one-line
# one (re-emitted on the tomllib path) both match.
md_flat=$(printf '%s' "$md_toml" | tr -d ' \n')
if printf '%s' "$md_flat" | grep -qE 'also_copy=\["deploy/","static/",?\]' \
   && printf '%s' "$md_flat" | grep -qF 'pytest_add_cli_args_test_selection=["tests/"]' \
   && [ "$(printf '%s\n' "$md_toml" | grep -c '^source_paths')" -eq 1 ] \
   && ! printf '%s\n' "$md_toml" | grep -qF '"old"'; then
  echo "  ✓ the project's also_copy and test selection are carried; its own source_paths is replaced"; PASS=$((PASS + 1))
else
  echo "  ✗ expected also_copy and test selection carried, source_paths replaced"; printf '%s\n' "$md_toml" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi
# do_not_mutate and the neighbouring table need Python's tomllib (3.11+); run the
# same fixture there when this machine has such an interpreter.
md_py=""
for md_c in python3.13 python3.12 python3.11; do
  if command -v "$md_c" >/dev/null 2>&1; then md_py="$md_c"; break; fi
done
if [ -n "$md_py" ]; then
  cat >"$MD/wt/pyproject.toml" <<'EOF'
[tool.mutmut]
source_paths = ["old"]
also_copy = ["deploy/"]
do_not_mutate = ["*/migrations/*"]

[tool.other]
keep = true
EOF
  "$md_py" "$MD/inject.py" "$MD_TPL" "$MD/wt" app/y.py >"$HOOK_OUT" 2>&1
  if grep -qx 'do_not_mutate = \["\*/migrations/\*"\]' "$MD/wt/pyproject.toml" \
     && grep -qx 'also_copy = \["deploy/"\]' "$MD/wt/pyproject.toml" \
     && grep -qx 'keep = true' "$MD/wt/pyproject.toml" \
     && "$md_py" -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$MD/wt/pyproject.toml"; then
    echo "  ✓ ($md_py) every other [tool.mutmut] key is carried and the result still parses as TOML"; PASS=$((PASS + 1))
  else
    echo "  ✗ ($md_py) expected do_not_mutate and also_copy carried over"; sed 's/^/      /' "$MD/wt/pyproject.toml"; FAIL=$((FAIL + 1))
  fi
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
   && grep -qF 'in-process pytest runs' "$HOOK_OUT" \
   && grep -qF 'belongs in the suite' "$HOOK_OUT" && ! grep -q 'not checked' "$HOOK_OUT"; then
  echo "  ✓ \"Failed to run clean test\" exits 2 and explains the in-process state leak, not the advisory path"; PASS=$((PASS + 1))
else
  echo "  ✗ expected exit 2 with the state-leak explanation (got exit $md_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
if [ "$(wc -l <"$MD/count" | tr -d ' ')" -eq 1 ]; then
  echo "  ✓ mutmut ran exactly once: that failure is not retried"; PASS=$((PASS + 1))
else
  echo "  ✗ mutmut must run exactly once on that failure (ran $(wc -l <"$MD/count" | tr -d ' ') times)"; FAIL=$((FAIL + 1))
fi
rm -rf "$MD"
