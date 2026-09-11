#!/usr/bin/env bash
# Build the native macOS shell (SwiftUI + WKWebView) into a double-clickable .app.
# No Xcode project needed: swiftc from Command Line Tools is enough.
#
# Usage:
#   ./build-app.sh            # ad-hoc signed local build (default) -> build/DSH工作台.app
#   ./build-app.sh release    # Developer ID + Hardened Runtime + notarize -> build/DSH工作台-<版本>.app (+ .zip)
#
# release 需要（缺一个就明确报错，不会产出半成品）：
#   DEVELOPER_ID    Developer ID Application: Name (TEAMID)
#   NOTARY_PROFILE  notarytool 的钥匙串 profile 名（默认 dsh-notary）
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-adhoc}"
APP_NAME="DSH工作台"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
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
# 声明 zh-Hans 本地化目录，否则 AppKit/SwiftUI 自带的系统菜单与按钮（文件/编辑/窗口、
# 边栏开关…）会跟随开发区域回落到英文。App 自己的文案在 Sources/Copy.swift。
mkdir -p "${APP}/Contents/Resources/zh-Hans.lproj"
cat > "${APP}/Contents/Resources/zh-Hans.lproj/Localizable.strings" <<'STRINGS'
/* DSH 工作台：界面文案集中在 Sources/Copy.swift，这里只用于声明 zh-Hans 本地化。 */
STRINGS
find "${APP}" -name '.DS_Store' -delete
find "${APP}" -name '._*' -delete
xattr -rc "${APP}" 2>/dev/null || true

if [ "$MODE" = "release" ]; then
  : "${DEVELOPER_ID:?release 构建需要设置 DEVELOPER_ID（如 \"Developer ID Application: Name (TEAMID)\"）}"
  RELEASE_APP="build/${APP_NAME}-${VERSION}.app"
  rm -rf "$RELEASE_APP"
  cp -R "$APP" "$RELEASE_APP"
  APP="$RELEASE_APP"
  echo "==> Release 产物：${APP}（版本 ${VERSION}）"
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
  echo "==> Notarizing（提交 + 等待结果）"
  ditto -c -k --keepParent "${APP}" "build/${APP_NAME}-${VERSION}.zip"
  xcrun notarytool submit "build/${APP_NAME}-${VERSION}.zip" \
    --keychain-profile "${NOTARY_PROFILE:-dsh-notary}" --wait
  echo "==> Stapling"
  xcrun stapler staple "${APP}"
  codesign --verify --deep --strict --verbose=2 "${APP}"
  spctl --assess --type execute -vv "${APP}" || true
else
  # Ad-hoc signature (local personal use; not sandboxed so it can run docker CLI).
  codesign --force --deep --sign - "${APP}" 2>/dev/null || codesign --force --sign - "${APP}"
fi

echo "==> Done: $(pwd)/${APP}"
echo "Open with: open \"${APP}\""
if [ "$MODE" = "release" ]; then
  echo "分发 zip: $(pwd)/build/${APP_NAME}-${VERSION}.zip"
fi
