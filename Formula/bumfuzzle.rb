class Bumfuzzle < Formula
  desc "Config-driven guardrails and scaffolding for AI coding agents"
  homepage "https://github.com/arc-com/bumfuzzle"
  url "https://github.com/arc-com/bumfuzzle/archive/refs/tags/v1.2.2.tar.gz"
  # populated by .github/workflows/release.yml on tag push
  sha256 "0fdae28c5464ae5b5354a5d0ab94207dfbc9399ea6025c8b3ec8567b5d354f2c"
  license "MIT"

  depends_on "yq"
  depends_on "python@3.12"

  def install
    libexec.install "bumfuzzle.sh", "eval-rules.sh", "bumfuzzle-template.yml", "index.html", "scripts", "VERSION"
    bin.install_symlink libexec/"bumfuzzle.sh" => "bumfuzzle"
    bin.install_symlink libexec/"bumfuzzle.sh" => "bfz"
  end

  test do
    system bin/"bumfuzzle", "--help"
  end
end
