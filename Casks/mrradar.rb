# Homebrew cask for MRRadar.
#
#   brew tap ardasnturk/mrradar https://github.com/ardasnturk/mrradar
#   brew install --cask mrradar
#
# `version` and `sha256` are updated by scripts/prepare-release.sh.
cask "mrradar" do
  version "0.1.1"
  sha256 "95ee206940bd59e0b8b78971c94e485ee41c163c726352bdfd47ea0da57e0331"

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
