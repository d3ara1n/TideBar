#!/bin/bash
# 组装可分发的 TideBar.app 并签名、打 zip。
# 用法: scripts/build-app.sh <version>   （缺省时本地开发版用 0.0.0）
# 只产出构建产物（dist/），不注册任何系统状态。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
IDENTITY="TideBar Signing"
APP="TideBar.app"
DIST="dist"

echo "── swift build (release) ──"
swift build -c release

STAGING="$DIST/$APP"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"

echo "── 组装 bundle ──"
cp .build/release/TideBar "$STAGING/Contents/MacOS/"
cp -R .build/release/TideBar_TideBar.bundle "$STAGING/Contents/Resources/"
cp brand/composer/AppIcon.icns "$STAGING/Contents/Resources/"

cat > "$STAGING/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TideBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.dearain.TideBar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TideBar</string>
    <key>CFBundleDisplayName</key>
    <string>TideBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $(date +%Y) dearain. All rights reserved.</string>
    <key>SUFeedURL</key>
    <string>https://github.com/d3ara1n/TideBar/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>nPOwF817jWyg1G9Cx/jk7uSH2NhNTBMdVJ7QdIGaAZk=</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

mkdir -p "$STAGING/Contents/Resources/en.lproj" "$STAGING/Contents/Resources/zh-Hans.lproj"
cat > "$STAGING/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOF'
"CFBundleDisplayName" = "TideBar";
"CFBundleName" = "TideBar";
EOF
cat > "$STAGING/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'EOF'
"CFBundleDisplayName" = "汐";
"CFBundleName" = "汐";
EOF

echo "── 签名 ($IDENTITY) ──"
codesign --force --sign "$IDENTITY" "$STAGING"
codesign --verify --strict "$STAGING"

echo "── 打包 zip ──"
mkdir -p "$DIST"
rm -f "$DIST/TideBar-$VERSION.zip"
ditto -c -k --keepParent "$STAGING" "$DIST/TideBar-$VERSION.zip"

plutil -lint "$STAGING/Contents/Info.plist"
echo "✅ $DIST/$APP ($VERSION) → $DIST/TideBar-$VERSION.zip ($(du -h "$DIST/TideBar-$VERSION.zip" | cut -f1))"
