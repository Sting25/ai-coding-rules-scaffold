<!-- ai-coding-rules-scaffold:test-guard:begin -->

## Test-guard: red-green (opt-in gate)

Installed by `install.sh --test-guard`. On every PR, CI runs `.githooks/lib/check-red-green`: each NEW test runs against the base commit and must FAIL there (rule 6).

- **A new test that legitimately passes on base** (characterization before a refactor, coverage backfill) carries a marker with a required reason:
  `@pytest.mark.characterization(reason="pinning invoice rounding before refactor")`.
  Never add markers in bulk to get past the gate.
- **Known limit:** a test in a file whose imports exist only on this branch cannot run on base; it counts as red and is reported by file. Put tests for existing behavior in a file that imports only existing code.

<!-- ai-coding-rules-scaffold:test-guard:end -->
