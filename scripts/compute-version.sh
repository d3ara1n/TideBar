#!/bin/bash
# 相对上个 v* tag 计算下个版本号（conventional commits 驱动）：
#   breaking → major，feat → minor，fix/perf/refactor → patch
# 无上个 tag 时以 0.0.0 为基线（首个 feat 版本即 0.1.0）。
# 输出：新版本号（无 v 前缀）；无可发布变更时无输出。
set -euo pipefail
cd "$(dirname "$0")/.."

last_tag=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [[ -n "$last_tag" ]]; then
    base="${last_tag#v}"
    range="$last_tag..HEAD"
else
    base="0.0.0"
    range="HEAD"
fi
IFS='.' read -r major minor patch <<< "$base"

level=""
while IFS= read -r hash; do
    msg=$(git log -1 --format='%B' "$hash")
    first_line=$(head -1 <<< "$msg")
    pattern='^([a-z]+)(\([^)]*\))?(!)?:'
    [[ "$first_line" =~ $pattern ]] || continue
    type="${BASH_REMATCH[1]}"
    breaking="false"
    [[ "${BASH_REMATCH[3]}" == "!" ]] && breaking="true"
    tail -n +2 <<< "$msg" | grep -q 'BREAKING CHANGE:' && breaking="true"

    if [[ "$breaking" == "true" ]]; then
        level="major"
    elif [[ "$type" == "feat" && -z "$level" ]] || [[ "$type" == "feat" && "$level" == "patch" ]]; then
        level="minor"
    elif [[ "$type" =~ ^(fix|perf|refactor)$ && -z "$level" ]]; then
        level="patch"
    fi
done < <(git log --format='%H' "$range" 2>/dev/null)

case "$level" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *)     exit 0 ;;
esac
