#!/usr/bin/env bash
# build-tipa.sh — 在 macOS runner 上从指定 sing-box 源码构建 iOS .tipa
#
# 通过环境变量驱动：
#   SB_REPO        (必需) sing-box 源码仓库 (owner/repo)
#   SB_REF         (必需) 要 clone 的分支或 tag
#   TAG_NAME       (必需) 版本号，用于 tipa 文件名
#   MERGE_TAG      (可选) clone 后额外合入的上游 tag，例 v1.14.0-beta.9
#   UPSTREAM_REPO  (可选) MERGE_TAG 的来源仓库，默认 SagerNet/sing-box
#   UPDATE_APPLE   (可选) "true" 时重新拉取最新 sing-box-for-apple
#   DISPLAY_SUFFIX (可选) CFBundleDisplayName 后缀
#   BUNDLE_ID      (可选) 覆盖 PRODUCT_BUNDLE_IDENTIFIER
#   OUTPUT_NAME    (可选) 产物文件名，默认 sing-box-${TAG_NAME}.tipa
#
# 产物写入 ${GITHUB_WORKSPACE}，兼容 macOS 自带 bash 3.2。
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}" "${TAG_NAME:?missing TAG_NAME}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
APPLICATION_NAME=sing-box
OUTPUT_NAME="${OUTPUT_NAME:-${APPLICATION_NAME}-${TAG_NAME}.tipa}"

cd "$HOME"
rm -rf sing-box

echo "${BUILD_LABEL:-sing-box}-v${TAG_NAME}" >> "$SUMMARY"
echo "sing-box source: ${SB_REPO}@${SB_REF}" >> "$SUMMARY"
# 不用 --depth 1：libbox 通过 git describe --tags 内嵌版本号，需要完整 tag 历史
git clone -b "${SB_REF}" --recurse-submodules --filter=blob:none "https://github.com/${SB_REPO}.git" sing-box

if [ "${UPDATE_APPLE:-false}" = "true" ]; then
  rm -rf sing-box/clients/apple
  git clone --recurse-submodules --depth 1 https://github.com/SagerNet/sing-box-for-apple.git sing-box/clients/apple
fi

cd "$HOME/sing-box"

if [ -n "${MERGE_TAG:-}" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git remote add upstream "https://github.com/${UPSTREAM_REPO:-SagerNet/sing-box}.git"
  git fetch upstream "refs/tags/${MERGE_TAG}:refs/tags/${MERGE_TAG}"
  git merge --no-edit "${MERGE_TAG}"
  # 上游 tag 可能更新了 clients/apple 的 submodule 指针
  git submodule update --init --recursive
  echo "merged upstream ${MERGE_TAG}" >> "$SUMMARY"
fi

echo "embedded version: $(git describe --tags)" >> "$SUMMARY"

make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
go run ./cmd/internal/build_libbox -target apple -platform ios
mv Libbox.xcframework clients/apple

cd clients/apple

XCODE_EXTRA=()
if [ -n "${DISPLAY_SUFFIX:-}" ]; then
  XCODE_EXTRA[${#XCODE_EXTRA[@]}]="INFOPLIST_KEY_CFBundleDisplayName=${APPLICATION_NAME}${DISPLAY_SUFFIX}"
fi
if [ -n "${BUNDLE_ID:-}" ]; then
  XCODE_EXTRA[${#XCODE_EXTRA[@]}]="PRODUCT_BUNDLE_IDENTIFIER=${BUNDLE_ID}"
fi

xcodebuild \
  -project sing-box.xcodeproj \
  -scheme SFI \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath DerivedData \
  build \
  STRIP_INSTALLED_PRODUCT=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  ${XCODE_EXTRA[@]+"${XCODE_EXTRA[@]}"}

APP_PATH="DerivedData/Build/Products/Release-iphoneos/${APPLICATION_NAME}.app"
ldid -SSFI/SFI.entitlements "${APP_PATH}/${APPLICATION_NAME}"
ldid -SExtension/Extension.entitlements "${APP_PATH}/PlugIns/Extension.appex/Extension"
ldid -SIntentsExtension/IntentsExtension.entitlements "${APP_PATH}/Extensions/IntentsExtension.appex/IntentsExtension"

mkdir -p packages/Payload
cp -rp "${APP_PATH}" packages/Payload
cd packages
zip -qr "${APPLICATION_NAME}.tipa" Payload
mv "${APPLICATION_NAME}.tipa" "${GITHUB_WORKSPACE}/${OUTPUT_NAME}"
cd "${GITHUB_WORKSPACE}"
echo -e "SHA256 Checksum: \n$(sha256sum "${OUTPUT_NAME}")" >> "$SUMMARY"

rm -rf "$HOME/sing-box"
