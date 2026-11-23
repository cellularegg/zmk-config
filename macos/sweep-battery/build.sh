#!/bin/sh
# Builds SweepBattery.app and installs it to ~/Applications.
# Usage: ./build.sh            (build + install + launch)
set -eu
cd "$(dirname "$0")"

app=build/SweepBattery.app
rm -rf build
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O main.swift -o "$app/Contents/MacOS/SweepBattery"
codesign --force --sign - "$app"

pkill -x SweepBattery 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/SweepBattery.app
cp -R "$app" ~/Applications/
open ~/Applications/SweepBattery.app
echo "Installed ~/Applications/SweepBattery.app"
