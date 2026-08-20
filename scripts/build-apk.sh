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

bash "$(dirname "$0")/prepare-source-android.sh"
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

# build_libbox 仅在 ../sing-box-for-android/app/libs 已存在时才会自动拷贝 aar
mkdir -p "$ANDROID_DIR/app/libs"
make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
go run ./cmd/internal/build_libbox -target android

# 兜底：若自动拷贝未发生，从 sing-box 工作目录手动拷入
for aar in libbox.aar libbox-legacy.aar; do
  if [ ! -f "$ANDROID_DIR/app/libs/$aar" ] && [ -f "$PREPARE_DIR/$aar" ]; then
    cp -f "$PREPARE_DIR/$aar" "$ANDROID_DIR/app/libs/$aar"
    echo "copied $aar into android app/libs (fallback)"
  fi
done
if [ ! -f "$ANDROID_DIR/app/libs/libbox.aar" ]; then
  echo "libbox.aar missing under $ANDROID_DIR/app/libs after build_libbox" >&2
  ls -la "$PREPARE_DIR"/*.aar 2>/dev/null || true
  ls -la "$ANDROID_DIR/app/libs" || true
  exit 1
fi

cd "$ANDROID_DIR"
ls -la app/libs

case "$BUILD_VARIANT" in
  debug)
    ./gradlew --no-daemon :app:assembleOtherDebug :app:assembleOtherLegacyDebug
    ;;
  release)
    ./gradlew --no-daemon :app:assembleOtherRelease :app:assembleOtherLegacyRelease
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
# 优先上传 universal；若无则上传全部 ABI，保留原文件名避免互相覆盖
collect_apks() {
  local dir="$1" label="$2"
  local apks=()
  local f
  for f in "$dir"/*-universal-*.apk "$dir"/*universal*.apk; do
    [ -f "$f" ] || continue
    apks+=("$f")
  done
  if [ "${#apks[@]}" -eq 0 ]; then
    for f in "$dir"/*.apk; do
      [ -f "$f" ] || continue
      apks+=("$f")
    done
  fi
  for f in "${apks[@]+"${apks[@]}"}"; do
    idx=$((idx + 1))
    base="$(basename "$f")"
    name="${OUTPUT_PREFIX}-${TAG_NAME}-${label}-${base#SFA-}"
    if [ -f "${DEST_DIR}/${name}" ]; then
      name="${OUTPUT_PREFIX}-${TAG_NAME}-${label}-${idx}.apk"
    fi
    cp -f "$f" "${DEST_DIR}/${name}"
    echo "apk: ${name} (from ${base})" >> "$SUMMARY"
    echo -e "SHA256 ${name}:\n$(sha256sum "${DEST_DIR}/${name}")" >> "$SUMMARY"
  done
}

case "$BUILD_VARIANT" in
  debug)
    collect_apks app/build/outputs/apk/other/debug other
    collect_apks app/build/outputs/apk/otherLegacy/debug otherLegacy
    ;;
  release)
    collect_apks app/build/outputs/apk/other/release other
    collect_apks app/build/outputs/apk/otherLegacy/release otherLegacy
    ;;
esac
shopt -u nullglob

if [ "$idx" -eq 0 ]; then
  echo "no apk produced" >&2
  find app/build/outputs -type f -name '*.apk' 2>/dev/null || true
  exit 1
fi
