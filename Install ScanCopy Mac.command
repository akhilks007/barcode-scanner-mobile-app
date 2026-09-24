#!/bin/bash
# Builds the ScanCopy Mac helper and installs it into /Applications.
# Double-click this file in Finder (it opens in Terminal).
set -euo pipefail
cd "$(dirname "$0")"

# Use full Xcode even if the command-line tools are selected.
if [ -d "/Applications/Xcode.app" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "▶ Building ScanCopy Mac (this takes a minute)…"
xcodebuild -project ScanCopy.xcodeproj -target ScanCopyMac -configuration Release \
  SYMROOT="$PWD/build" -allowProvisioningUpdates -quiet build

APP="build/Release/ScanCopyMac.app"
if [ ! -d "$APP" ]; then
  echo "✖ Build failed — open ScanCopy.xcodeproj in Xcode, select the ScanCopyMac scheme and press ⌘B to see the error."
  read -r -p "Press Return to close…"
  exit 1
fi

echo "▶ Installing to /Applications…"
pkill -x ScanCopyMac 2>/dev/null || true
sleep 1
rm -rf "/Applications/ScanCopyMac.app"
ditto "$APP" "/Applications/ScanCopyMac.app"

echo "▶ Starting ScanCopy Mac…"
open "/Applications/ScanCopyMac.app"

echo ""
echo "✔ Done. ScanCopy Mac is installed and will open automatically at login."
echo "  If this is the first install (or typing stops working), click the barcode icon in the"
echo "  menu bar → Grant Access… and switch ScanCopyMac ON in Accessibility."
read -r -p "Press Return to close…"
