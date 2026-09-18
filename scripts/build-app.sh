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
# --build-system native：swiftbuild 后端会把 LC_BUILD_VERSION 的 sdk 写成部署目标，
# 产物会被系统按旧外观渲染；native 后端写入真实 SDK 版本
swift build -c release --build-system native

STAGING="$DIST/$APP"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"

echo "── 组装 bundle ──"
cp .build/release/TideBar "$STAGING/Contents/MacOS/"

# Sparkle 为动态 framework（官方 Developer ID 签名，保留原签不重签）
if [ -d .build/release/Sparkle.framework ]; then
    mkdir -p "$STAGING/Contents/Frameworks"
    cp -R .build/release/Sparkle.framework "$STAGING/Contents/Frameworks/"
    # SPM 扁平布局的 rpath 是 @loader_path；bundle 内 framework 在 ../Frameworks
    install_name_tool -add_rpath @loader_path/../Frameworks "$STAGING/Contents/MacOS/TideBar"
fi
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
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
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

# 外观门禁：系统按 LC_BUILD_VERSION.sdk 做新外观的 linked-on-or-after 判定，
# sdk < 26 的产物会被渲染成旧样式，禁止发布
echo "── 校验二进制 SDK 标记 ──"
SDK=$(xcrun vtool -show-build "$STAGING/Contents/MacOS/TideBar" | awk '$1=="sdk"{print $2}')
SDK_MAJOR=${SDK%%.*}
if [ -z "$SDK" ] || [ "$SDK_MAJOR" -lt 26 ]; then
    echo "❌ LC_BUILD_VERSION.sdk=$SDK（需 ≥26）：产物会被按旧外观渲染，禁止发布" >&2
    exit 1
fi
echo "✅ LC_BUILD_VERSION.sdk=$SDK"

echo "── 打包 zip ──"
mkdir -p "$DIST"
rm -f "$DIST/TideBar-$VERSION.zip"
ditto -c -k --keepParent "$STAGING" "$DIST/TideBar-$VERSION.zip"

plutil -lint "$STAGING/Contents/Info.plist"
echo "✅ $DIST/$APP ($VERSION) → $DIST/TideBar-$VERSION.zip ($(du -h "$DIST/TideBar-$VERSION.zip" | cut -f1))"
