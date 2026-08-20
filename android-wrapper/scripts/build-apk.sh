#!/usr/bin/env bash
# build-apk.sh — 从指定 sing-box 源码构建 Android APK
#
# 环境变量：
#   SB_REPO / SB_REF / TAG_NAME / MERGE_TAG / UPSTREAM_REPO
#   ANDROID_REPO / ANDROID_REF
#   BUILD_VARIANT  debug|release（默认 debug，旁加载无需自备 keystore）
#   OUTPUT_PREFIX  产物前缀，默认 sing-box
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}" "${TAG_NAME:?missing TAG_NAME}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
BUILD_VARIANT="${BUILD_VARIANT:-debug}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-sing-box}"
PREPARE_DIR="${PREPARE_DIR:-$HOME/sing-box}"
ANDROID_DIR="${ANDROID_DIR:-$HOME/sing-box-for-android}"

echo "${OUTPUT_PREFIX}-android-v${TAG_NAME}" >> "$SUMMARY"
echo "sing-box source: ${SB_REPO}@${SB_REF}" >> "$SUMMARY"
echo "build variant: ${BUILD_VARIANT}" >> "$SUMMARY"

bash "$(dirname "$0")/prepare-source.sh"
cd "$PREPARE_DIR"
[ -z "${MERGE_TAG:-}" ] || echo "overlaid own files onto upstream ${MERGE_TAG}" >> "$SUMMARY"
echo "embedded version: $(git describe --tags)" >> "$SUMMARY"
echo "android client: $(git -C "$ANDROID_DIR" rev-parse --short HEAD)" >> "$SUMMARY"

# release 签名材料：须在 clone Android 客户端之后写入（prepare 会 rm -rf ANDROID_DIR）
if [ "$BUILD_VARIANT" = "release" ]; then
  if [ -z "${RELEASE_KEYSTORE_BASE64:-}" ]; then
    echo "release build needs RELEASE_KEYSTORE_BASE64" >&2
    exit 1
  fi
  echo "$RELEASE_KEYSTORE_BASE64" | base64 -d > "$ANDROID_DIR/app/release.keystore"
fi

# gomobile / libbox → 自动拷到 ../sing-box-for-android/app/libs
make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
go run ./cmd/internal/build_libbox -target android

cd "$ANDROID_DIR"
mkdir -p app/libs
ls -la app/libs

case "$BUILD_VARIANT" in
  debug)
    ./gradlew --no-daemon :app:assembleOtherDebug :app:assembleOtherLegacyDebug
    OUT_GLOB1=app/build/outputs/apk/other/debug/*.apk
    OUT_GLOB2=app/build/outputs/apk/otherLegacy/debug/*.apk
    ;;
  release)
    ./gradlew --no-daemon :app:assembleOtherRelease :app:assembleOtherLegacyRelease
    OUT_GLOB1=app/build/outputs/apk/other/release/*.apk
    OUT_GLOB2=app/build/outputs/apk/otherLegacy/release/*.apk
    ;;
  *)
    echo "unknown BUILD_VARIANT: $BUILD_VARIANT (want debug|release)" >&2
    exit 1
    ;;
esac

./gradlew --stop || true

DEST_DIR="${GITHUB_WORKSPACE:-.}"
mkdir -p "$DEST_DIR"
shopt -s nullglob
idx=0
for apk in $OUT_GLOB1 $OUT_GLOB2; do
  idx=$((idx + 1))
  base="$(basename "$apk")"
  # SFA-x.y.z-xxx.apk → sing-box-<tag>-other[Legacy].apk
  if [[ "$apk" == *otherLegacy* ]]; then
    name="${OUTPUT_PREFIX}-${TAG_NAME}-otherLegacy.apk"
  else
    name="${OUTPUT_PREFIX}-${TAG_NAME}-other.apk"
  fi
  cp -f "$apk" "${DEST_DIR}/${name}"
  echo "apk: ${name} (from ${base})" >> "$SUMMARY"
  echo -e "SHA256 ${name}:\n$(sha256sum "${DEST_DIR}/${name}")" >> "$SUMMARY"
done
shopt -u nullglob

if [ "$idx" -eq 0 ]; then
  echo "no apk produced" >&2
  find app/build/outputs -type f -name '*.apk' 2>/dev/null || true
  exit 1
fi
