#!/usr/bin/env bash

# FluxDO 发版脚本
# 用法: ./scripts/release.sh [版本号] [--pre]
# 示例: ./scripts/release.sh 0.1.0
#       ./scripts/release.sh 0.1.0-beta --pre

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查参数
if [ -z "$1" ]; then
    error "请指定版本号，例如: ./scripts/release.sh 0.1.0"
fi

VERSION=$1
IS_PRERELEASE=false

if [ "$2" == "--pre" ]; then
    IS_PRERELEASE=true
fi

# 验证版本号格式
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    error "版本号格式错误，应为: x.y.z 或 x.y.z-beta"
fi

# 提取主版本号（去掉预发布标识）
VERSION_NAME=$(echo $VERSION | sed 's/-.*$//')

# 检查是否在 git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "当前目录不是 git 仓库"
fi

# 检查是否有未提交的更改
if ! git diff-index --quiet HEAD --; then
    error "存在未提交的更改，请先提交或暂存"
fi

# 检查是否在 main 分支
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    warn "当前不在 main 分支 (当前: $CURRENT_BRANCH)"
    read -p "是否继续? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 检查 tag 是否已存在
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    error "Tag v$VERSION 已存在"
fi

# 读取当前 pubspec.yaml 版本
PUBSPEC_FILE="pubspec.yaml"
if [ ! -f "$PUBSPEC_FILE" ]; then
    error "找不到 pubspec.yaml 文件"
fi

CURRENT_VERSION=$(grep "^version:" $PUBSPEC_FILE | sed 's/version: //' | sed 's/+.*//')

info "当前版本: $CURRENT_VERSION"
info "新版本: $VERSION"

# 生成 Version Code (基于日期时间)
VERSION_CODE=$(date +%Y%m%d%H)

info "Version Code: $VERSION_CODE"

# 确认发版
echo ""
echo "=========================================="
echo "  发版信息"
echo "=========================================="
echo "版本号: $VERSION"
echo "Version Name: $VERSION_NAME"
echo "Version Code: $VERSION_CODE"
echo "类型: $([ "$IS_PRERELEASE" == "true" ] && echo "预发布版" || echo "稳定版")"
echo "分支: $CURRENT_BRANCH"
echo "=========================================="
echo ""

read -p "确认发版? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
fi

# 更新 pubspec.yaml
info "更新 pubspec.yaml..."
sed -i.bak "s/^version:.*/version: $VERSION_NAME+$VERSION_CODE/" $PUBSPEC_FILE
rm -f $PUBSPEC_FILE.bak

# 提交版本号变更
info "提交版本号变更..."
git add $PUBSPEC_FILE
git commit -m "chore: bump version to $VERSION

Co-Authored-By: Release Script <noreply@github.com>"

# 推送到远程
info "推送到远程仓库..."
git push

# 创建并推送 tag
info "创建 tag v$VERSION..."
git tag -a "v$VERSION" -m "Release v$VERSION"

info "推送 tag..."
git push origin "v$VERSION"

# 完成
echo ""
echo "=========================================="
echo -e "${GREEN}✓ 发版成功!${NC}"
echo "=========================================="
echo "Tag: v$VERSION"
echo "GitHub Actions: https://github.com/Lingyan000/fluxdo/actions"
echo "Releases: https://github.com/Lingyan000/fluxdo/releases"
echo "=========================================="
echo ""

if [ "$IS_PRERELEASE" == "true" ]; then
    info "这是预发布版，不会生成 Changelog"
else
    info "稳定版会自动生成 Changelog 并提交到 main 分支"
fi
