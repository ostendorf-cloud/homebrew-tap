class Proof < Formula
  desc "Scratch formula that proves the formula check, never merged"
  homepage "https://github.com/ostendorf-cloud/homebrew-tap"
  url "https://github.com/ostendorf-cloud/homebrew-tap/archive/b45c056c22a7ffd8af6c346d50659bbc7917598e.tar.gz"
  version "0.0.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "Apache-2.0"

  def install
    pkgshare.install "LICENSE"
  end

  test do
    assert_path_exists pkgshare/"LICENSE"
  end
end
