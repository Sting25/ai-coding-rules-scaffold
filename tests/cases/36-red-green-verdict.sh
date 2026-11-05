# shellcheck shell=bash
# cases/36-red-green-verdict.sh: the --test-guard gate's actual VERDICT.
# Sourced into the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are
# already in scope.
#
# WHAT cases/27 DOES NOT COVER. Every functional assertion there hits a guard
# clause that returns before any gate logic runs: check-red-green.template:141
# (`if not pathlib.Path("tests").exists(): return 0`) is 175 lines above the
# only blocking arm, and check-mutation-diff exits at its verify_mutmut()
# pre-check. So the 329 lines that decide PASS or BLOCK — the worktree overlay,
# the new-node-ID difference, the per-test classification, the characterization
# exemption, the `return 1 if failed else 0` at :315 — could regress to an
# unconditional `return 0` (a bad refactor of still_offending, a broken
# `git worktree add`, a pytest node-ID format change) and this whole suite would
# stay green. The commit that added the gate says the real behaviour was
# verified BY HAND and never encoded; this file encodes it.
#
# EIGHTEEN CHECKS (seventeen pytest verdicts plus a static one; (f)-(p) are the
# moved-test exemption), on one shared fixture whose base commit ships a deliberately
# WRONG `add(a, b) -> a - b` plus a test pinned to that wrong behaviour:
#   (a) a new test that FAILS on base  -> exit 0. The false-positive direction,
#       and the one that matters most: a gate that blocks honest red-green work
#       gets switched off within a week, so this is the assertion that keeps it
#       usable.
#   (b) a new test that PASSES on base, unmarked -> exit 1, naming the offender.
#       The gate's whole reason to exist (arXiv 2412.14137: generated suites
#       DISCARD the tests that fail, keeping the ones that pass by construction).
#   (c) the same green-on-base test, marked @pytest.mark.characterization
#       -> exit 0. The named exception must actually work, or the gate's only
#       escape hatch is a dead end and (b) becomes unbypassable.
#
# A root conftest.py is what puts the repo root on sys.path so `from calc import
# add` resolves under pytest's rootdir insertion; it is NOT a test path by
# check-red-green's is_test_path(), so it is never overlaid and stays identical
# in the base worktree.
#
# THE PYTEST DEPENDENCY, stated rather than hidden. check-red-green shells out
# to `sys.executable -m pytest`, so the four pytest assertions cannot run without
# pytest importable. .github/workflows/test.yml installs ruff and zizmor but NOT
# pytest, so in CI today this is a counted SKIP that shows up in the driver's
# final Result line, not a silent pass — adding a pinned `pip install pytest`
# step to test.yml is what turns it into real CI coverage.

echo "cases/36: check-red-green's blocking verdict (#140)"

if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  echo "  - SKIP: pytest not importable — check-red-green's 17 verdict assertions did NOT run (add a pinned 'pip install pytest' step to .github/workflows/test.yml to cover this in CI)"
  SKIP=$((SKIP + 17))
else
  # A fixture repo with the --test-guard artifacts installed, one BASE commit,
  # and HEAD == base. Scenarios below add the second commit. Printed as
  # "<dir> <base_sha>" so the caller needs no second git call.
  #
  # The build runs in a subshell so a failed `cd` cannot strand the driver in a
  # temp dir, but its log goes to $HOOK_OUT rather than /dev/null and its status
  # is RETURNED. An earlier revision sent both to /dev/null: a broken install.sh
  # then produced an empty $() and the run died several lines later inside a
  # scenario with `printf: /calc.py: No such file or directory`, which names
  # neither the fixture nor the assertion that did not run. _rg_new below turns
  # that into one labelled failure with the build log attached.
  _rg_fixture() {
    local t rc=0
    t=$(mktemp -d)
    (
      cd "$t" || exit 1
      git init --quiet
      git config user.email "test@test.local"
      git config user.name "Scaffold Test"
      printf '[project]\nname = "rg"\nversion = "0"\n' >pyproject.toml
      : >conftest.py
      mkdir tests
      # The bug the PR under test is pretending to fix.
      printf 'def add(a, b):\n    return a - b\n' >calc.py
      printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >tests/test_calc.py
      "$SCAFFOLD_DIR/install.sh" --python --no-verify --test-guard
      git add -A
      git commit --quiet -m "base" --no-verify  # scaffold-allow: test fixture
    ) >"$HOOK_OUT" 2>&1 || rc=$?
    # The artifact under test must actually exist: --test-guard silently doing
    # nothing would otherwise surface as three confusing "exit 127" verdicts.
    if [ "$rc" -ne 0 ] || [ ! -f "$t/.githooks/lib/check-red-green" ]; then
      printf 'fixture build failed (rc=%s), .githooks/lib/check-red-green %s\n' \
        "$rc" "$([ -f "$t/.githooks/lib/check-red-green" ] && echo present || echo MISSING)" >>"$HOOK_OUT"
      rm -rf "$t"
      return 1
    fi
    printf '%s %s' "$t" "$(git -C "$t" rev-parse HEAD)"
  }

  # _rg_new: build a fixture and publish it as $_rg_dir/$_rg_base. On failure it
  # books ONE named FAIL with the build log and returns 1, so the caller skips
  # its scenario instead of running assertions against a directory that is not
  # there.
  _rg_new() {
    local out
    if ! out=$(_rg_fixture); then
      echo "  ✗ could not build the red-green fixture repo — this verdict was NOT tested"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
      return 1
    fi
    read -r _rg_dir _rg_base <<<"$out"
  }

  # _rg_run <dir> <base_sha>: run the INSTALLED check (cases/27 proves it is
  # byte-identical to the shipped template) and echo its exit code. Output lands
  # in $HOOK_OUT for the caller to grep, so a verdict can never pass on the exit
  # code alone while the message says something else.
  _rg_run() {
    local rc=0
    ( cd "$1" && python3 .githooks/lib/check-red-green --base "$2" ) >"$HOOK_OUT" 2>&1 || rc=$?
    printf '%s' "$rc"
  }

  # (a) RED on base: HEAD fixes add() and adds a test that could not have passed
  #     before the fix. Must be allowed through.
  if _rg_new; then
    printf 'def add(a, b):\n    return a + b\n' >"$_rg_dir/calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 10\n\n\ndef test_add_is_a_sum():\n    assert add(2, 3) == 5\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "fix add, with a red-on-base test" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 0 ] && grep -q 'red on base, as required: 1 test' "$HOOK_OUT"; then
      echo "  ✓ a new test that fails on base is allowed through (exit 0, counted red)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a red-on-base new test must exit 0 and be counted red (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (b) GREEN on base, unmarked: HEAD changes no source and adds a test that
  #     already passes against base. Must be blocked, and must NAME the node ID
  #     — a bare exit 1 is not actionable.
  if _rg_new; then
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n\n\ndef test_add_five_five():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "add a test that passes on base" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 1 ] \
       && grep -q 'green-on-base: tests/test_calc.py::test_add_five_five' "$HOOK_OUT" \
       && grep -q 'PASS against' "$HOOK_OUT"; then
      echo "  ✓ a new test that passes on base is blocked, naming the offending node ID (exit 1)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a green-on-base new test must exit 1 naming the node ID (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (c) GREEN on base, MARKED: identical to (b) plus the documented marker with
  #     a reason. The exception must be honoured, or (b) has no way out.
  if _rg_new; then
    printf 'import pytest\n\nfrom calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n\n\n@pytest.mark.characterization(reason="pinning add before the refactor")\ndef test_add_five_five():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "add a characterization test" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 0 ] && grep -q 'exempt (characterization): tests/test_calc.py::test_add_five_five' "$HOOK_OUT"; then
      echo "  ✓ a green-on-base test marked @pytest.mark.characterization is exempted (exit 0)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a characterization-marked green-on-base test must be exempted and exit 0 (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (d) A killed earlier run left a STALE worktree registration (directory gone,
  #     .git/worktrees/<name> still there). The gate prunes before it adds
  #     (#221), so the registration is gone afterwards and the verdict is
  #     unaffected. Same HEAD as (a), so the gate really reaches `worktree add`.
  if _rg_new; then
    printf 'def add(a, b):\n    return a + b\n' >"$_rg_dir/calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 10\n\n\ndef test_add_is_a_sum():\n    assert add(2, 3) == 5\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "fix add, with a red-on-base test" --no-verify  # scaffold-allow: test fixture
    _rg_stale="$_rg_dir/stale-wt"
    git -C "$_rg_dir" worktree add --quiet --detach "$_rg_stale" HEAD >/dev/null 2>&1
    rm -rf "$_rg_stale"
    _rg_pre=$(git -C "$_rg_dir" worktree list --porcelain | grep -c "stale-wt" || true)
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    _rg_post=$(git -C "$_rg_dir" worktree list --porcelain | grep -c "stale-wt" || true)
    if [ "$_rg_pre" -eq 1 ] && [ "$_rg_post" -eq 0 ] && [ "$_rg_rc" -eq 0 ]; then
      echo "  ✓ a stale worktree registration is pruned before the gate adds its own (exit 0)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ stale registration must exist before (got $_rg_pre), be gone after (got $_rg_post), gate exit 0 (got $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (f)-(p): the moved-test exemption (#200). A new node ID that is green on base
  # is exempt only when it is a TRUE MOVE: the same [Class::]name[param] tail
  # existed at base, that base node ID is gone at HEAD, the function AST is the
  # same, and every module-level name it uses is bound the same way in both
  # files. The base's only test is test_add_existing (passes on base:
  # add(5, 5) == 0), so a copy of it in a NEW file is a new, green-on-base ID.
  # _rg_check <label> <want_rc> <grep_pattern> <forbid_exempt 1|0>: run the gate
  # and book one PASS/FAIL. With forbid_exempt=1 the output must also hold no
  # "exempt (moved" line. The scenario's HEAD commit is made by the caller.
  _rg_check() {
    local label=$1 want=$2 pat=$3 forbid_exempt=$4 pat2=${5:-} ok=0
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq "$want" ] && grep -q "$pat" "$HOOK_OUT" \
       && { [ -z "$pat2" ] || grep -q "$pat2" "$HOOK_OUT"; }; then ok=1; fi
    if [ "$ok" -eq 1 ] && { [ "$forbid_exempt" -eq 0 ] || ! grep -q 'exempt (moved' "$HOOK_OUT"; }; then
      echo "  ✓ $label (exit $want)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ $label: want exit $want matching '$pat', got exit $_rg_rc"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  }
  _rg_commit() { git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "$1" --no-verify; }  # scaffold-allow: test fixture
  # _rg_rebase <msg>: commit the scenario's extra BASE files and make that commit the base.
  _rg_rebase() { _rg_commit "$1" && _rg_base=$(git -C "$_rg_dir" rev-parse HEAD); }
  _rg_moved='exempt (moved, body and context unchanged)'
  # A parametrized test over a module-level table, in base.
  _rg_table='import pytest\nfrom calc import add\n\nCASES = [(5, 5)]\n\n\n@pytest.mark.parametrize("a, b", CASES)\ndef test_add_equal_operands(a, b):\n    assert add(a, b) == 0\n'

  # (f) moved verbatim into a new file, deleted from the old one, importing `add`
  #     exactly as before: exempt.
  if _rg_new; then
    printf 'from calc import add  # noqa: F401\n' >"$_rg_dir/tests/test_calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc_more.py"
    _rg_commit "split: move test_add_existing"
    _rg_check "a test moved verbatim to a new file (same import of add) is exempt" 0 \
      "$_rg_moved: tests/test_calc_more.py::test_add_existing" 0
  fi

  # (g) moved AND reformatted (quotes, trailing comma, re-wrapped call, a docstring).
  #     In place a reformat keeps the node ID, so it is never "new"; it is the
  #     move that makes it a new ID, and the AST equivalence is what exempts it.
  if _rg_new; then
    printf 'from calc import add  # noqa: F401\n' >"$_rg_dir/tests/test_calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    """A docstring, which carries no semantics."""\n    assert (\n        add(\n            5,\n            5,\n        )\n        == 0\n    )\n' >"$_rg_dir/tests/test_calc_fmt.py"
    _rg_commit "format and move"
    _rg_check "a moved test reformatted (wrapping, trailing comma, docstring) is exempt" 0 \
      "$_rg_moved: tests/test_calc_fmt.py::test_add_existing" 0
  fi

  # (h) moved with a semantic edit that STILL passes on base: add(5, 5) == 0 becomes
  #     add(4, 4) == 0 (a - b is 0 for equal operands). Body differs: offender.
  if _rg_new; then
    printf 'from calc import add  # noqa: F401\n' >"$_rg_dir/tests/test_calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(4, 4) == 0\n' >"$_rg_dir/tests/test_calc_more.py"
    _rg_commit "move with an edit"
    _rg_check "a moved test with a changed assertion stays an offender" 1 \
      'green-on-base: tests/test_calc_more.py::test_add_existing' 1
  fi

  # (i) fail closed PER FILE: the base also holds an unparsable, never-collected
  #     file. It cannot hold a candidate, so it only removes candidates; it must
  #     not switch the exemption off for the rest of the tree.
  if _rg_new; then
    printf 'def broken(:\n' >"$_rg_dir/tests/helper_broken.py"
    _rg_rebase "base also holds an unparsable helper"
    printf 'from calc import add  # noqa: F401\n' >"$_rg_dir/tests/test_calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc_more.py"
    _rg_commit "move with an unparsable unrelated base file"
    _rg_check "an unparsable unrelated base file does not block a legitimate move" 0 \
      "$_rg_moved: tests/test_calc_more.py::test_add_existing" 0
  fi

  # (i2) a test whose only base copy sits in a file the predicate cannot read
  #      (latin-1 source, byte 0xe9 in a comment; pytest honours the coding
  #      cookie, the predicate decodes UTF-8) has no readable candidate: offender.
  if _rg_new; then
    printf '# -*- coding: latin-1 -*-\n# caf\351\nfrom calc import add\n\n\ndef test_legacy_check():\n    assert add(3, 3) == 0\n' >"$_rg_dir/tests/test_legacy.py"
    _rg_rebase "base holds a latin-1 test file"
    rm "$_rg_dir/tests/test_legacy.py"
    printf 'from calc import add\n\n\ndef test_legacy_check():\n    assert add(3, 3) == 0\n' >"$_rg_dir/tests/test_legacy_moved.py"
    _rg_commit "move out of the unreadable file"
    _rg_check "a test whose only base copy is in an unreadable file stays an offender" 1 \
      'green-on-base: tests/test_legacy_moved.py::test_legacy_check' 1
  fi

  # (j1) a NEW parametrize case added in place to a module-level table: the
  #      table is not a new test body, but the node ID is new and green on base.
  if _rg_new; then
    printf '%b' "$_rg_table" >"$_rg_dir/tests/test_cases.py"
    _rg_rebase "base holds a parametrized test"
    _rg_old='(5, 5)]'; _rg_new_cases='(5, 5), (4, 4)]'
    printf '%b' "${_rg_table/"$_rg_old"/$_rg_new_cases}" >"$_rg_dir/tests/test_cases.py"
    _rg_commit "add a case to the table"
    _rg_check "a new parametrize case added to a module-level table is an offender" 1 \
      'green-on-base: tests/test_cases.py::test_add_equal_operands\[4-4\]' 1
  fi

  # (j2) the same parametrized test MOVED with an identical table: exempt.
  if _rg_new; then
    printf '%b' "$_rg_table" >"$_rg_dir/tests/test_cases.py"
    _rg_rebase "base holds a parametrized test"
    printf '# moved\n' >"$_rg_dir/tests/test_cases.py"
    printf '%b' "$_rg_table" >"$_rg_dir/tests/test_cases_more.py"
    _rg_commit "move the parametrized test"
    _rg_check "a moved parametrized test with the same cases and table is exempt" 0 \
      "$_rg_moved: tests/test_cases_more.py::test_add_equal_operands\[5-5\]" 0
  fi

  # (k) a verbatim COPY with the original left in place is not a move: offender.
  if _rg_new; then
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc_copy.py"
    _rg_commit "copy the test, keep the original"
    _rg_check "a verbatim copy with the original still present is an offender" 1 \
      'green-on-base: tests/test_calc_copy.py::test_add_existing' 1
  fi

  # (l) moved body whose new file REDEFINES a helper it calls: add() now returns
  #     0 locally, so the same text means something else. Offender.
  if _rg_new; then
    printf '# moved\n' >"$_rg_dir/tests/test_calc.py"
    printf 'def add(a, b):\n    return 0\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc_more.py"
    _rg_commit "move into a file with its own add"
    _rg_check "a moved test whose new file redefines the helper it calls is an offender" 1 \
      'green-on-base: tests/test_calc_more.py::test_add_existing' 1
  fi

  # (m) a move PLUS a new parametrize case whose table lives in ANOTHER module
  #     (tests/data.py grows). The table is not in the moved file, so only the
  #     tail comparison tells the new [4-4] from the moved [5-5]: [4-4] has no
  #     base ID with that tail, so it stays an offender, while [5-5] is exempt.
  if _rg_new; then
    printf 'CASES = [(5, 5)]\n' >"$_rg_dir/tests/data.py"
    : >"$_rg_dir/tests/__init__.py"
    printf 'import pytest\nfrom calc import add\nfrom tests.data import CASES\n\n\n@pytest.mark.parametrize("a, b", CASES)\ndef test_eq(a, b):\n    assert add(a, b) == 0\n' >"$_rg_dir/tests/test_p.py"
    _rg_rebase "base holds a parametrized test over an imported table"
    printf 'CASES = [(5, 5), (4, 4)]\n' >"$_rg_dir/tests/data.py"
    mv "$_rg_dir/tests/test_p.py" "$_rg_dir/tests/test_p2.py"
    _rg_commit "move the test and grow the imported table"
    _rg_check "a move plus a new case in an imported table: the new case is an offender, the moved one is exempt" 1 \
      'green-on-base: tests/test_p2.py::test_eq\[4-4\]' 0 \
      "$_rg_moved: tests/test_p2.py::test_eq\[5-5\]"
  fi

  # (n) moved test that requests a module-level FIXTURE by parameter name, and the
  #     new file redefines that fixture: same test text, different meaning. Offender.
  if _rg_new; then
    printf 'import pytest\nfrom calc import add\n\n\n@pytest.fixture\ndef val():\n    return add(5, 5)\n\n\ndef test_v(val):\n    assert val == 0\n' >"$_rg_dir/tests/test_f.py"
    _rg_rebase "base holds a fixture and a test that requests it"
    printf '# moved\n' >"$_rg_dir/tests/test_f.py"
    printf 'import pytest\nfrom calc import add\n\n\n@pytest.fixture\ndef val():\n    return 0\n\n\ndef test_v(val):\n    assert val == 0\n' >"$_rg_dir/tests/test_f2.py"
    _rg_commit "move the test into a file with its own val fixture"
    _rg_check "a moved test whose module-level fixture is redefined in the new file is an offender" 1 \
      'green-on-base: tests/test_f2.py::test_v' 1
  fi

  # (o) moved CLASS test whose sibling method on the same class is redefined in
  #     the new file (the class header alone is identical). Offender.
  if _rg_new; then
    printf 'from calc import add\n\n\nclass TestA:\n    def helper(self):\n        return add(5, 5)\n\n    def test_a(self):\n        assert self.helper() == 0\n' >"$_rg_dir/tests/test_c.py"
    _rg_rebase "base holds a class with a helper method"
    printf '# moved\n' >"$_rg_dir/tests/test_c.py"
    printf 'from calc import add\n\n\nclass TestA:\n    def helper(self):\n        return 0\n\n    def test_a(self):\n        assert self.helper() == 0\n' >"$_rg_dir/tests/test_c2.py"
    _rg_commit "move the class into a file with a different helper"
    _rg_check "a moved class test whose sibling method is redefined in the new file is an offender" 1 \
      'green-on-base: tests/test_c2.py::TestA::test_a' 1
  fi

  # (p) a verbatim move whose HEAD file is not valid UTF-8 (latin-1 cookie, byte
  #     0xe9 in a comment; pytest collects it, the predicate cannot decode it):
  #     fail closed, nothing is exempted.
  if _rg_new; then
    printf '# moved\n' >"$_rg_dir/tests/test_calc.py"
    printf '# -*- coding: latin-1 -*-\n# caf\xe9\nfrom calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_more.py"
    _rg_commit "move into a file the predicate cannot decode"
    _rg_check "a moved test whose HEAD file is not valid UTF-8 stays an offender" 1 \
      'green-on-base: tests/test_more.py::test_add_existing' 1
  fi

  unset _rg_dir _rg_base _rg_rc
  unset -f _rg_fixture _rg_new _rg_run _rg_check _rg_commit _rg_rebase
  unset _rg_moved _rg_table _rg_old _rg_new_cases
fi
unset _rg_stale _rg_pre _rg_post

# (e) check-mutation-diff cannot be driven here (it needs mutmut and a mutation
#     run, too heavy for this suite), so cover its prune-on-start statically:
#     the prune call must come BEFORE the `worktree add` in the shipped template.
_rg_pl=$(grep -n '^ *run(\["git", "worktree", "prune"\])' "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" | head -1 | cut -d: -f1)
_rg_al=$(grep -n '"worktree", "add"' "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" | head -1 | cut -d: -f1)
if [ -n "$_rg_pl" ] && [ -n "$_rg_al" ] && [ "$_rg_pl" -lt "$_rg_al" ]; then
  echo "  ✓ check-mutation-diff prunes worktrees before it adds one (static: line $_rg_pl < $_rg_al)"
  PASS=$((PASS + 1))
else
  echo "  ✗ check-mutation-diff must call git worktree prune before git worktree add (prune: ${_rg_pl:-none}, add: ${_rg_al:-none})"
  FAIL=$((FAIL + 1))
fi
unset _rg_pl _rg_al
