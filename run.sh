#!/bin/bash
# Quick build & run Yap
set -e
cd "$(dirname "$0")"

echo "⚙️  Building..."
xcodegen generate -q 2>/dev/null
xcodebuild -project Yap.xcodeproj -scheme Yap -configuration Debug build 2>&1 | grep -E "error:|BUILD"

echo "🚀 Launching..."
osascript -e 'tell application "Yap" to quit' 2>/dev/null || true
sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/Yap-*/Build/Products/Debug/Yap.app
echo "✅ Yap is running"
