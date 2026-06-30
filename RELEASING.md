# Releasing

The **git tag is the single source of truth** for the version. Everything else
(the `package.json` version, the README clone pin, the Homebrew formula) is a
derived copy that must be updated to match in the same release. This checklist
keeps them from drifting.

The version lives in these places — all must agree on `vX.Y.Z`:

| Place | File | What to change |
|-------|------|----------------|
| git tag | — | annotated tag `vX.Y.Z` |
| changelog | `CHANGELOG.md` | promote `[Unreleased]` → `[vX.Y.Z] — DATE` |
| README pin | `README.md` | the `git clone --branch vX.Y.Z` line |
| npm | `package.json` | `"version": "X.Y.Z"` |
| Homebrew | `packaging/homebrew/ai-coding-rules-scaffold.rb` + the tap | `url` (tag) + `sha256` |

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

## 2. Tag + GitHub release

```sh
git checkout main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"
git push origin vX.Y.Z
# Release notes = the CHANGELOG section for this version:
awk '/^## \[vX\.Y\.Z\]/{f=1} /^## \[/{if(f && !/vX\.Y\.Z/)exit} f' CHANGELOG.md > /tmp/notes.md
gh release create vX.Y.Z --title "vX.Y.Z — <summary>" --notes-file /tmp/notes.md
```

Confirm it's latest: `gh release list` shows `vX.Y.Z` marked **Latest**.

## 3. Publish to npm

```sh
npm publish            # needs `npm login` first; npm may prompt for a 2FA OTP
npm view ai-coding-rules-scaffold version   # confirm it shows X.Y.Z
```

The package has zero dependencies, so there's no lockfile to manage. `npx
ai-coding-rules-scaffold` resolves the new version automatically.

## 4. Update the Homebrew tap

The formula's `url` points at the GitHub source tarball for the tag; bump the
`url` + recompute the `sha256`:

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

## 5. Smoke-test both registries

```sh
# npm
npx -y ai-coding-rules-scaffold@X.Y.Z --help
# Homebrew
brew install sting25/tap/ai-coding-rules-scaffold && ai-coding-rules-scaffold --help
```

## Future: automate

This is currently manual on purpose (it needs the maintainer's npm + GitHub
auth). A `release.yml` triggered on tag push could publish to npm (with an
`NPM_TOKEN` secret) and open a PR to the tap bumping `url`/`sha256` (with a
tap-scoped PAT) — deriving every copy from the tag so steps 3–4 can't drift.
Worth adding once the cadence justifies the secret setup.
