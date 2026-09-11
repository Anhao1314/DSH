#!/usr/bin/env bash
# Build the native macOS shell (SwiftUI + WKWebView) into a double-clickable .app.
# No Xcode project needed: swiftc from Command Line Tools is enough.
#
# Usage:
#   ./build-app.sh            # ad-hoc signed local build (default)
#   ./build-app.sh release    # Developer ID signing + notarization (needs DEVELOPER_ID)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-adhoc}"
APP_NAME="DSH工作台"
APP="build/${APP_NAME}.app"

echo "==> Compiling Swift sources ($MODE)"
rm -rf build && mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
SOURCES=$(find Sources -name '*.swift' | sort)
swiftc -swift-version 5 -O -parse-as-library \
  -target arm64-apple-macosx13.0 \
  $SOURCES \
  -o "${APP}/Contents/MacOS/DSHTeam"

echo "==> Building icon"
[ -f Assets/AppIcon.icns ] || ./make-icon.sh

echo "==> Assembling bundle"
cp Info.plist "${APP}/Contents/Info.plist"
cp Assets/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
find "${APP}" -name '.DS_Store' -delete
find "${APP}" -name '._*' -delete
xattr -rc "${APP}" 2>/dev/null || true

if [ "$MODE" = "release" ]; then
  : "${DEVELOPER_ID:?release 构建需要设置 DEVELOPER_ID（如 \"Developer ID Application: Name (TEAMID)\"）}"
  echo "==> Signing with Developer ID + hardened runtime"
  # entitlements：只保留最低限度（本地网络 + 用户选择的文件），不做沙盒。
  ENTITLEMENTS="build/DSHTeam.entitlements"
  mkdir -p build
  cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict>
</plist>
PLIST
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "${APP}"
  echo "==> Notarizing"
  ditto -c -k --keepParent "${APP}" "build/${APP_NAME}.zip"
  xcrun notarytool submit "build/${APP_NAME}.zip" --keychain-profile "${NOTARY_PROFILE:-dsh-notary}" --wait
  xcrun stapler staple "${APP}"
else
  # Ad-hoc signature (local personal use; not sandboxed so it can run docker CLI).
  codesign --force --deep --sign - "${APP}" 2>/dev/null || codesign --force --sign - "${APP}"
fi

echo "==> Done: $(pwd)/${APP}"
echo "Open with: open \"${APP}\""
