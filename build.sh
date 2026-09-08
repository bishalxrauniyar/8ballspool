#!/bin/sh
# Builds 8BallsPool.app — a floating 8-ball pool game for your macOS desktop.
set -e
cd "$(dirname "$0")"

mkdir -p 8BallsPool.app/Contents/MacOS 8BallsPool.app/Contents/Resources

swiftc -O -swift-version 5 main.swift \
    -o 8BallsPool.app/Contents/MacOS/8BallsPool \
    -framework AppKit -framework Carbon -framework AVFoundation -framework QuartzCore

cp Info.plist 8BallsPool.app/Contents/Info.plist

sh makeicon.sh >/dev/null 2>&1 || true
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns 8BallsPool.app/Contents/Resources/AppIcon.icns
fi

codesign --force --sign - 8BallsPool.app 2>/dev/null || true

echo "Built 8BallsPool.app — open it and play."
