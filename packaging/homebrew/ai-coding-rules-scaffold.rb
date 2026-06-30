# Homebrew formula for ai-coding-rules-scaffold.
#
# CANONICAL SOURCE. The installable copy lives in the tap repo
# (Sting25/homebrew-tap) as Formula/ai-coding-rules-scaffold.rb; this copy is
# version-controlled here so it's reviewed alongside the code and validated in
# CI. On each release, bump `url` (the tag) + `sha256` and sync this file to the
# tap (see RELEASING.md). The sha256 is of the GitHub source tarball:
#   curl -fsSL .../archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
class AiCodingRulesScaffold < Formula
  desc "Pre-commit and CI guardrails: size, pattern, secret, and hygiene checks"
  homepage "https://github.com/Sting25/ai-coding-rules-scaffold"
  url "https://github.com/Sting25/ai-coding-rules-scaffold/archive/refs/tags/v0.9.0.tar.gz"
  sha256 "38c2b1ee5b732ff41a7440ba3a85513132ff47c66b29ee7b189176a36400aa34"
  license "MIT"

  def install
    # The installer is pure bash and reads its templates from its own directory,
    # writing only into the caller's cwd — so stage the whole tree in libexec and
    # expose a wrapper on PATH that execs it. Args (--both, --frontend, …) pass
    # straight through; the wrapper inherits the user's cwd as the install target.
    #
    # Dir["*"] alone SKIPS dotfiles, dropping .github/ and the dot-templates
    # (.scaffold.toml.template, .coveragerc.template, .prettierrc.json.template,
    # .prettierignore.template) that install.sh copies — so glob both and exclude
    # only "." / "..". (Release tarballs carry no .git, so this is safe.)
    # Drop only the "." / ".." self/parent entries; keep everything else,
    # dotfiles included. The skip list is hoisted out of the block so there's no
    # array literal inside it (brew style: Performance/CollectionLiteralInLoop).
    skip = [".", ".."]
    entries = (Dir["*"] + Dir[".*"]).reject { |f| skip.include?(File.basename(f)) }
    libexec.install entries
    (bin/"ai-coding-rules-scaffold").write <<~SH
      #!/bin/bash
      exec "#{libexec}/install.sh" "$@"
    SH
  end

  def caveats
    <<~EOS
      Run it from your project's root to install the guardrails into that repo:
        ai-coding-rules-scaffold            # auto-detects Python / JS
        ai-coding-rules-scaffold --both     # or pick the stack explicitly
        ai-coding-rules-scaffold --help     # all flags

      The optional agent guardrails (--claude / --cursor) need jq:
        brew install jq
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/ai-coding-rules-scaffold --help")

    # Full install into a throwaway repo — exercises the whole template copy, not
    # just --help, so a missing-bundle regression (e.g. dropped dotfiles like
    # .github/workflows/lint.yml.template) fails the formula test, not the user.
    (testpath/"proj").mkpath
    cd testpath/"proj" do
      system "git", "init", "-q"
      system "git", "config", "user.email", "t@example.com"
      system "git", "config", "user.name", "Test"
      (testpath/"proj/package.json").write('{"name":"t"}')
      system bin/"ai-coding-rules-scaffold", "--frontend", "--no-verify"
      assert_path_exists testpath/"proj/.githooks/pre-commit"
      assert_path_exists testpath/"proj/.forbidden-patterns/secrets.txt"
      assert_path_exists testpath/"proj/.github/workflows/lint.yml"
    end
  end
end
