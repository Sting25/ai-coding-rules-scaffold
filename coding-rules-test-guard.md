<!-- ai-coding-rules-scaffold:test-guard:begin -->

## Test-guard: red-green (opt-in gate)

Installed by `install.sh --test-guard`. CI runs `.githooks/lib/check-red-green`
on every PR: each NEW test is executed against the base commit and must FAIL
there. A test that has never been observed to fail has never been shown to
test anything; a suite generated against an implementation passes by
construction.

- **Confirm every new test fails without the change it accompanies** (write
  the failing test first, or check it against the base branch yourself).
  "It passes on my branch" is not evidence.
- **A new test that legitimately passes on base** (characterization of
  existing behaviour before a refactor, coverage backfill for code that was
  already correct) must say so out loud:
  `@pytest.mark.characterization(reason="pinning invoice rounding before refactor")`.
  The reason is required. An exception you have to name is a decision; an
  exception the tool infers is a hole.
- **Never weaken the gate to get past it** (deleting the workflow, blanket
  characterization markers, `--no-verify`). Make the test fail on base, or
  state in the PR why it cannot.
- Known limit, stated by the check itself: a test in a file whose imports
  only exist on this branch cannot be executed on base at all; it is counted
  as red and reported by file. Put tests for pre-existing behaviour in a file
  that imports only existing code, so the gate can actually see them.

<!-- ai-coding-rules-scaffold:test-guard:end -->
