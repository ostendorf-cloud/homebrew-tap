class Proof < Formula
  desc "Scratch formula that proves the formula check, never merged"
  homepage "https://github.com/ostendorf-cloud/homebrew-tap"
  url "https://github.com/ostendorf-cloud/homebrew-tap/archive/b45c056c22a7ffd8af6c346d50659bbc7917598e.tar.gz"
  version "0.0.1"
  sha256 "f68c997d4f8cc94c89bac741d646fc2fa86db15707abe77fbd810e1281702fb9"
  license "Apache-2.0"

  def install
    pkgshare.install "LICENSE"
  end

  test do
    assert_path_exists pkgshare/"LICENSE"
  end
end
