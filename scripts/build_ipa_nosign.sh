#!/bin/bash
# 构建 iOS 无签名 IPA 包
# 用法: ./scripts/build_ipa_nosign.sh [版本号]
# 示例: ./scripts/build_ipa_nosign.sh 0.2.3

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 从 pubspec.yaml 读取版本号
VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | head -1 | awk '{print $2}' | cut -d'+' -f1)
if [ -n "$1" ]; then
  VERSION="$1"
fi

IPA_DIR="$PROJECT_ROOT/build/ios/ipa"
IPA_NAME="fluxdo-${VERSION}-nosign.ipa"

echo "=== 构建 iOS 无签名 IPA ($VERSION) ==="

cd "$PROJECT_ROOT"

# 构建
echo ">>> flutter build ios --release --no-codesign"
flutter build ios --release --no-codesign

# 打包 IPA
echo ">>> 打包 IPA..."
mkdir -p "$IPA_DIR"
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/Payload"
cp -r "$PROJECT_ROOT/build/ios/iphoneos/Runner.app" "$TMPDIR/Payload/"
cd "$TMPDIR"
zip -qr "$IPA_DIR/$IPA_NAME" Payload
rm -rf "$TMPDIR"

echo ""
echo "=== 完成 ==="
echo "IPA 路径: $IPA_DIR/$IPA_NAME"
ls -lh "$IPA_DIR/$IPA_NAME"
