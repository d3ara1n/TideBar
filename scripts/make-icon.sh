#!/bin/bash
# 从 Icon Composer 源文件 (brand/composer/app.icon) 生成传统 AppIcon.icns。
# 仅本地改图后运行，产物提交仓库；CI 构建只消费成品，不依赖 ictool。
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
SRC="brand/composer/app.icon"
OUT="brand/composer/AppIcon.icns"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

for pair in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
    size=${pair%%:*}
    scale=${pair##*:}
    name="icon_${size}x${size}"
    [[ $scale == 2 ]] && name="${name}@2x"
    "$ICTOOL" "$SRC" --export-image \
        --output-file "$SET/${name}.png" \
        --platform macOS --rendition Default \
        --width "$size" --height "$size" --scale "$scale" >/dev/null
done

iconutil -c icns -o "$OUT" "$SET"
echo "生成 $OUT ($(du -h "$OUT" | cut -f1))"
