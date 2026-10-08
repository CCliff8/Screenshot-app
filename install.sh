#!/bin/zsh
# Builds Snip from source and installs it to /Applications.
set -e
cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then echo "Snip only runs on macOS."; exit 1; fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 15 ]]; then
  echo "Snip requires macOS 15 (Sequoia) or later."; exit 1
fi
if ! command -v swift >/dev/null; then
  echo "Swift not found. Install the Xcode Command Line Tools first:  xcode-select --install"; exit 1
fi

./build.sh
pkill -x Snip 2>/dev/null || true
rm -rf /Applications/Snip.app
cp -R Snip.app /Applications/
echo "Installed to /Applications/Snip.app"
open /Applications/Snip.app
