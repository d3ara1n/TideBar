#!/bin/bash
# 组装可分发的 TideBar.app 并签名、打 zip。
# 用法: scripts/build-app.sh <version>   （缺省时本地开发版用 0.0.0）
# 只产出构建产物（dist/），不注册任何系统状态。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
IDENTITY="TideBar Signing"
PRODUCT="TideBar"
APP="$PRODUCT.app"
APP_RESOURCE_BUNDLE="TideBar_TideBar.bundle"
DIST="dist"

echo "── swift build (release) ──"
# swiftbuild 的资源 accessor 原生查找 Contents/Resources，但 Xcode 27 会把
# LC_BUILD_VERSION.sdk 错写成部署目标。显式 platform_version 同时固定最低系统与真实 SDK；
# 下方 vtool 门禁会再次校验最终二进制，禁止错误标记进入发布包。
DEPLOYMENT_TARGET="14.0"
SDK_VERSION="$(xcrun --show-sdk-version)"
BUILD_ARGUMENTS=(
    -c release
    --build-system swiftbuild
    -Xlinker -platform_version
    -Xlinker macos
    -Xlinker "$DEPLOYMENT_TARGET"
    -Xlinker "$SDK_VERSION"
)
swift build "${BUILD_ARGUMENTS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
BUILD_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"

# 工具链升级后若资源 accessor 行为变化，在发布阶段立即失败，不留到用户机器闪退。
RESOURCE_ACCESSORS=()
while IFS= read -r -d '' accessor; do
    RESOURCE_ACCESSORS+=("$accessor")
done < <(find "$BUILD_ROOT" -path '*/DerivedSources/resource_bundle_accessor.swift' -print0)

if (( ${#RESOURCE_ACCESSORS[@]} == 0 )); then
    echo "❌ 未找到 SwiftPM 资源 accessor，无法保证发布包资源可定位" >&2
    exit 1
fi
for accessor in "${RESOURCE_ACCESSORS[@]}"; do
    if ! grep -q 'Bundle.main.resourceURL' "$accessor"; then
        echo "❌ 资源 accessor 未支持 Contents/Resources：$accessor" >&2
        exit 1
    fi
done

STAGING="$DIST/$APP"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"

echo "── 组装 bundle ──"
cp "$BUILD_DIR/$PRODUCT" "$STAGING/Contents/MacOS/"

# 所有 SwiftPM 资源 bundle 统一放入标准 Contents/Resources；swiftbuild 的 accessor 让
# TideBar 与第三方 package 使用同一套位置规则，新增带资源依赖后无需修改此脚本。
shopt -s nullglob
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
FRAMEWORKS=("$BUILD_DIR"/*.framework)
shopt -u nullglob

FOUND_APP_RESOURCE=false
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    name="$(basename "$bundle")"
    cp -R "$bundle" "$STAGING/Contents/Resources/"
    echo "  resource: Contents/Resources/$name"
    if [[ "$name" == "$APP_RESOURCE_BUNDLE" ]]; then
        FOUND_APP_RESOURCE=true
    fi
done
if [[ "$FOUND_APP_RESOURCE" != true ]]; then
    echo "❌ 缺少主程序资源：$BUILD_DIR/$APP_RESOURCE_BUNDLE" >&2
    exit 1
fi

# 顶层 binary framework 统一嵌入标准 Frameworks 目录；保留供应方原始签名。
if (( ${#FRAMEWORKS[@]} > 0 )); then
    mkdir -p "$STAGING/Contents/Frameworks"
    for framework in "${FRAMEWORKS[@]}"; do
        cp -R "$framework" "$STAGING/Contents/Frameworks/"
        echo "  framework: $(basename "$framework")"
    done
    # SwiftPM 扁平布局通常使用 @rpath；bundle 内 framework 在 ../Frameworks。
    install_name_tool -add_rpath @loader_path/../Frameworks "$STAGING/Contents/MacOS/$PRODUCT"
fi

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
    <string>$DEPLOYMENT_TARGET</string>
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

echo "── 校验依赖完整性 ──"
# 复制后再次逐项核对，避免脚本演进时静默漏装某个 SwiftPM 资源包。
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    name="$(basename "$bundle")"
    destination="$STAGING/Contents/Resources/$name"
    if [[ ! -d "$destination" ]]; then
        echo "❌ 资源 bundle 未嵌入：$name" >&2
        exit 1
    fi
done

# 系统库无需随包分发；所有其他主程序动态依赖必须能在应用包内解析。
MISSING_DEPENDENCIES=()
while IFS= read -r dependency; do
    case "$dependency" in
        /System/*|/usr/lib/*)
            continue
            ;;
        @rpath/*)
            embedded="$STAGING/Contents/Frameworks/${dependency#@rpath/}"
            ;;
        @loader_path/../Frameworks/*)
            embedded="$STAGING/Contents/Frameworks/${dependency#@loader_path/../Frameworks/}"
            ;;
        @executable_path/../Frameworks/*)
            embedded="$STAGING/Contents/Frameworks/${dependency#@executable_path/../Frameworks/}"
            ;;
        @loader_path/*)
            embedded="$STAGING/Contents/MacOS/${dependency#@loader_path/}"
            ;;
        @executable_path/*)
            embedded="$STAGING/Contents/MacOS/${dependency#@executable_path/}"
            ;;
        *)
            MISSING_DEPENDENCIES+=("$dependency")
            continue
            ;;
    esac
    if [[ ! -e "$embedded" ]]; then
        MISSING_DEPENDENCIES+=("$dependency")
    fi
done < <(otool -L "$STAGING/Contents/MacOS/$PRODUCT" | awk 'NR > 1 { print $1 }')

if (( ${#MISSING_DEPENDENCIES[@]} > 0 )); then
    printf '❌ 未嵌入的非系统动态依赖：\n' >&2
    printf '  %s\n' "${MISSING_DEPENDENCIES[@]}" >&2
    exit 1
fi
echo "✅ ${#RESOURCE_BUNDLES[@]} 个资源 bundle、${#FRAMEWORKS[@]} 个 framework 已完整嵌入"

echo "── 签名 ($IDENTITY) ──"
codesign --force --sign "$IDENTITY" "$STAGING"
codesign --verify --deep --strict "$STAGING"

# 外观门禁：系统按 LC_BUILD_VERSION.sdk 做新外观的 linked-on-or-after 判定，
# sdk < 26 的产物会被渲染成旧样式，禁止发布
echo "── 校验二进制 SDK 标记 ──"
BUILD_VERSION=$(xcrun vtool -show-build "$STAGING/Contents/MacOS/$PRODUCT")
MIN_OS=$(awk '$1=="minos"{print $2}' <<< "$BUILD_VERSION")
SDK=$(awk '$1=="sdk"{print $2}' <<< "$BUILD_VERSION")
SDK_MAJOR=${SDK%%.*}
if [[ "$MIN_OS" != "$DEPLOYMENT_TARGET" || "$SDK" != "$SDK_VERSION" || "$SDK_MAJOR" -lt 26 ]]; then
    echo "❌ LC_BUILD_VERSION=minos $MIN_OS / sdk $SDK（预期 minos $DEPLOYMENT_TARGET / sdk $SDK_VERSION，且 sdk ≥26）" >&2
    exit 1
fi
echo "✅ LC_BUILD_VERSION=minos $MIN_OS / sdk $SDK"

echo "── 打包 zip ──"
mkdir -p "$DIST"
rm -f "$DIST/TideBar-$VERSION.zip"
ditto -c -k --keepParent "$STAGING" "$DIST/TideBar-$VERSION.zip"

plutil -lint "$STAGING/Contents/Info.plist"
echo "✅ $DIST/$APP ($VERSION) → $DIST/TideBar-$VERSION.zip ($(du -h "$DIST/TideBar-$VERSION.zip" | cut -f1))"
