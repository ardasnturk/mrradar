# Homebrew cask for MRRadar.
#
#   brew tap ardasnturk/mrradar https://github.com/ardasnturk/mrradar
#   brew install --cask mrradar
#
# `version` and `sha256` are updated by scripts/prepare-release.sh.
cask "mrradar" do
  version "0.1.0"
  sha256 "03d683a482abdaea01f1eb0d00c677a68c6940b66178ea1395318c29d2a9edaf"

  url "https://github.com/ardasnturk/mrradar/releases/download/v#{version}/MRRadar-#{version}.dmg"
  name "MRRadar"
  desc "Menu bar analytics and alerts for your subscription apps"
  homepage "https://github.com/ardasnturk/mrradar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "MRRadar.app"

  uninstall quit: "com.jastech.mrradar"

  zap trash: [
    "~/Library/Application Support/MRRadar",
    "~/Library/Preferences/com.jastech.mrradar.plist",
  ]
end
