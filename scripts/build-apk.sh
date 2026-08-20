#!/usr/bin/env bash
# build-apk.sh — 从指定 sing-box 源码构建 Android APK
#
# 环境变量：
#   SB_REPO / SB_REF / TAG_NAME / MERGE_TAG / UPSTREAM_REPO
#   ANDROID_REPO / ANDROID_REF
#   BUILD_VARIANT  debug|release（默认 debug，旁加载无需自备 keystore）
#   OUTPUT_PREFIX  产物前缀，默认 sing-box
#   APK_ABIS       逗号分隔 ABI，默认 arm64-v8a,x86_64
#                  （手机 / ARM Chromebook + Intel/AMD Chromebook）
#   APK_INCLUDE_LEGACY  true|false，默认 false（不编 Android 5 legacy 包）
#   APK_INCLUDE_UNIVERSAL true|false，默认 false（不上传四 ABI 合体包）
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}" "${TAG_NAME:?missing TAG_NAME}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
BUILD_VARIANT="${BUILD_VARIANT:-debug}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-sing-box}"
PREPARE_DIR="${PREPARE_DIR:-$HOME/sing-box}"
ANDROID_DIR="${ANDROID_DIR:-$HOME/sing-box-for-android}"
# 手机 + Chromebook：arm64 覆盖手机/ARM CB；x86_64 覆盖多数 Intel CB
APK_ABIS="${APK_ABIS:-arm64-v8a,x86_64}"
APK_INCLUDE_LEGACY="${APK_INCLUDE_LEGACY:-false}"
APK_INCLUDE_UNIVERSAL="${APK_INCLUDE_UNIVERSAL:-false}"

echo "${OUTPUT_PREFIX}-android-v${TAG_NAME}" >> "$SUMMARY"
echo "sing-box source: ${SB_REPO}@${SB_REF}" >> "$SUMMARY"
echo "build variant: ${BUILD_VARIANT}" >> "$SUMMARY"
echo "apk abis: ${APK_ABIS}" >> "$SUMMARY"
echo "include legacy: ${APK_INCLUDE_LEGACY}" >> "$SUMMARY"
echo "include universal: ${APK_INCLUDE_UNIVERSAL}" >> "$SUMMARY"

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

gradle_tasks=()
case "$BUILD_VARIANT" in
  debug)
    gradle_tasks+=(:app:assembleOtherDebug)
    if [ "$APK_INCLUDE_LEGACY" = "true" ]; then
      gradle_tasks+=(:app:assembleOtherLegacyDebug)
    fi
    ;;
  release)
    gradle_tasks+=(:app:assembleOtherRelease)
    if [ "$APK_INCLUDE_LEGACY" = "true" ]; then
      gradle_tasks+=(:app:assembleOtherLegacyRelease)
    fi
    ;;
  *)
    echo "unknown BUILD_VARIANT: $BUILD_VARIANT (want debug|release)" >&2
    exit 1
    ;;
esac

./gradlew --no-daemon "${gradle_tasks[@]}"
./gradlew --stop || true

DEST_DIR="${GITHUB_WORKSPACE:-.}"
mkdir -p "$DEST_DIR"
shopt -s nullglob
idx=0

# 按 ABI 列表收集分包；默认不传 universal（约 150MB+）
collect_apks() {
  local dir="$1" label="$2"
  local apks=()
  local f base name abi
  local -a want_abis=()
  IFS=',' read -r -a want_abis <<< "$APK_ABIS"

  for abi in "${want_abis[@]}"; do
    abi="$(echo "$abi" | tr -d '[:space:]')"
    [ -n "$abi" ] || continue
    for f in "$dir"/*-"${abi}"-*.apk; do
      [ -f "$f" ] || continue
      apks+=("$f")
    done
  done

  if [ "$APK_INCLUDE_UNIVERSAL" = "true" ]; then
    for f in "$dir"/*-universal-*.apk; do
      [ -f "$f" ] || continue
      apks+=("$f")
    done
  fi

  # 兜底：一个都没匹配到时上传目录内全部 apk，避免空产物
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
    if [ "$APK_INCLUDE_LEGACY" = "true" ]; then
      collect_apks app/build/outputs/apk/otherLegacy/debug otherLegacy
    fi
    ;;
  release)
    collect_apks app/build/outputs/apk/other/release other
    if [ "$APK_INCLUDE_LEGACY" = "true" ]; then
      collect_apks app/build/outputs/apk/otherLegacy/release otherLegacy
    fi
    ;;
esac
shopt -u nullglob

if [ "$idx" -eq 0 ]; then
  echo "no apk produced" >&2
  find app/build/outputs -type f -name '*.apk' 2>/dev/null || true
  exit 1
fi
