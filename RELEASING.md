# Releasing

The **git tag is the single source of truth** for the version. Everything else
(the `package.json` version, the README clone pin, the Homebrew formula) is a
derived copy that must be updated to match in the same release. This checklist
keeps them from drifting.

The version lives in these places — all must agree on `vX.Y.Z`:

| Place      | File                                                       | What to change                             |
| ---------- | ---------------------------------------------------------- | ------------------------------------------ |
| git tag    | —                                                          | annotated tag `vX.Y.Z`                     |
| changelog  | `CHANGELOG.md`                                             | promote `[Unreleased]` → `[vX.Y.Z] — DATE` |
| README pin | `README.md`                                                | the `git clone --branch vX.Y.Z` line       |
| npm        | `package.json`                                             | `"version": "X.Y.Z"`                       |
| Homebrew   | `packaging/homebrew/ai-coding-rules-scaffold.rb` + the tap | `url` (tag) + `sha256`                     |

## 1. Prepare (PR to `main`)

1. Make sure `main` is green on both runners and `CHANGELOG.md`'s `[Unreleased]`
   section lists everything since the last tag. (If entries were missed, back-fill
   them — the changelog is the release notes.)
2. Pick `X.Y.Z` per SemVer: bug-fix-only → patch; new features / behavior changes
   → minor; breaking consumer-facing changes → major.
3. In one PR:
   - Promote `[Unreleased]` → `## [vX.Y.Z] — YYYY-MM-DD` in `CHANGELOG.md`.
   - Bump the `git clone --branch` pin in `README.md`.
   - Bump `"version"` in `package.json`.
   - Run a self-lint dry run before pushing (a fat changelog can trip the secret
     scanner on its own prose):
     ```sh
     mkdir -p .githooks/lib .forbidden-patterns
     for t in githooks/lib/*.template; do cp "$t" ".githooks/lib/$(basename "$t" .template)"; done
     for t in forbidden-patterns/*.txt.template; do cp "$t" ".forbidden-patterns/$(basename "$t" .template)"; done
     git -c core.quotepath=off ls-files -z | .githooks/lib/check-secrets --ci
     ```
   - Open the PR, wait for CI green on **both** runners, merge (`--merge`, never
     `--auto` — this repo has no branch protection).

## 2. Push the tag — CI publishes (npm + GitHub release)

Once the prep PR is merged, tag `main` and push. The **`release.yml`** workflow
does the rest: runs the test suite, publishes to npm via **trusted publishing
(OIDC — no `NPM_TOKEN`, no 2FA prompt)** with provenance, and creates the GitHub
Release from the CHANGELOG section for the tag.

```sh
git checkout main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"
git push origin vX.Y.Z          # triggers release.yml
gh run watch                    # or watch the Actions tab
```

On success: `npm view ai-coding-rules-scaffold version` shows `X.Y.Z` (with a
provenance badge) and `gh release list` shows `vX.Y.Z` marked **Latest**. The
workflow fails **closed** if the tag doesn't match `package.json` (a tag pushed
without the prep bump aborts before touching the registry) or if the CHANGELOG
section is missing/empty (no blank release ships).

### One-time setup (per package — already done for this one)

OIDC publishing depends on a **Trusted Publisher** registered on npmjs.com. Do
this ONCE per package (all fields case-sensitive, exact):

npmjs.com → the package → **Settings → Trusted Publisher → GitHub Actions**:

- **Organization or user:** `Sting25`
- **Repository:** `ai-coding-rules-scaffold`
- **Workflow filename:** `release.yml`
- **Allowed actions:** `npm publish`

No token is stored anywhere. GitHub mints a short-lived OIDC token scoped to this
repo + workflow file; npm verifies it against the config above. (Requires npm
≥ 11.5.1 / Node ≥ 22.14 — the workflow pins Node 24, which bundles a new-enough npm.)

### Manual fallback (only if Actions is unavailable)

```sh
git tag -a vX.Y.Z -m "vX.Y.Z — <summary>" && git push origin vX.Y.Z
# Release notes = the CHANGELOG section for this version. The end-of-section guard
# is ANCHORED (`^## \[vX\.Y\.Z\]`) so an adjacent heading that merely CONTAINS the
# version as a substring (e.g. a `vX.Y.Z-hotfix`) can't leak its body into the notes.
awk '/^## \[vX\.Y\.Z\]/{f=1} /^## \[/{if(f && !/^## \[vX\.Y\.Z\]/)exit} f' CHANGELOG.md > /tmp/notes.md
[ -s /tmp/notes.md ] || { echo "ERROR: empty release notes — did you substitute vX.Y.Z?" >&2; exit 1; }
gh release create vX.Y.Z --title "vX.Y.Z — <summary>" --notes-file /tmp/notes.md
npm publish   # ⚠ manual publish needs a 2FA OTP or a bypass-enabled granular token
              #   (npm mandate). Trusted publishing above avoids both — prefer it.
```

## 3. Update the Homebrew tap — automated

The tap (`Sting25/homebrew-tap`) **bumps its own formula**. A `bump-formula`
workflow there points `Formula/ai-coding-rules-scaffold.rb` at the latest upstream
release (recomputing the `sha256`), using the tap's own `GITHUB_TOKEN` — no secret.

- **Instant:** after cutting the release, open the tap's **Actions → bump-formula
  → Run workflow**. It bumps within ~10s (or no-ops if already current).
- **Hands-off:** a 6-hour schedule catches it otherwise.

It's fail-safe: it validates the formula's Ruby syntax and that the new `url` +
`sha256` landed before committing, and leaves the formula untouched otherwise.

Also update the **canonical copy** in this repo (`packaging/homebrew/ai-coding-rules-scaffold.rb`)
in the next convenient PR so it doesn't drift from the tap — it's the versioned source of truth.

### Manual fallback (if the workflow is unavailable)

```sh
SHA=$(curl -fsSL https://github.com/Sting25/ai-coding-rules-scaffold/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256 | awk '{print $1}')
echo "$SHA"
```

Edit `packaging/homebrew/ai-coding-rules-scaffold.rb` (canonical source) — set the
`url` tag to `vX.Y.Z` and `sha256` to `$SHA` — then copy the file into the tap
(`Sting25/homebrew-tap` → `Formula/ai-coding-rules-scaffold.rb`) and push.

Validate before pushing the tap (with Homebrew installed):

```sh
brew style  packaging/homebrew/ai-coding-rules-scaffold.rb   # via a local tap; see below
brew install sting25/tap/ai-coding-rules-scaffold            # after the tap push
brew test    sting25/tap/ai-coding-rules-scaffold            # runs the install-into-a-repo assertions
brew uninstall ai-coding-rules-scaffold                      # clean up
```

> `brew style`/`audit` only apply the formula cops inside a tap. To lint locally:
> `brew tap-new you/localtest --no-git`, copy the `.rb` into its `Formula/`, then
> `brew style you/localtest/ai-coding-rules-scaffold`. Untap when done.

## 4. Smoke-test both registries

```sh
# npm
npx -y ai-coding-rules-scaffold@X.Y.Z --help
# Homebrew
brew install sting25/tap/ai-coding-rules-scaffold && ai-coding-rules-scaffold --help
```

## Fully automated — no secrets anywhere

The whole pipeline is now hands-off and **tokenless**:

- **npm publish + GitHub Release** — `release.yml` on tag push, via OIDC trusted
  publishing (no `NPM_TOKEN`).
- **Homebrew tap** — the tap's own `bump-formula` workflow, via its own
  `GITHUB_TOKEN` (no cross-repo PAT).

So a release is: merge the prep PR → push the tag → (optionally click the tap's
"Run workflow" for an instant Homebrew bump). No secret is stored in any repo.
