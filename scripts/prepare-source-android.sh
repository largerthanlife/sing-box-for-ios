#!/usr/bin/env bash
# prepare-source.sh — clone sing-box（+ 可选 overlay），并检出 Android 客户端到并列目录
#
# 环境变量：
#   SB_REPO / SB_REF / MERGE_TAG / UPSTREAM_REPO / OVERLAY_LIST / PREPARE_DIR
#   ANDROID_REPO   (可选) 默认 SagerNet/sing-box-for-android
#   ANDROID_REF    (可选) 默认 dev
#   ANDROID_DIR    (可选) 默认 $HOME/sing-box-for-android（须与 PREPARE_DIR 并列，供 build_libbox 拷贝 aar）
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}"
DEST="${PREPARE_DIR:-$HOME/sing-box}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY_LIST="${OVERLAY_LIST:-$SCRIPT_DIR/overlay-files.txt}"
ANDROID_REPO="${ANDROID_REPO:-SagerNet/sing-box-for-android}"
ANDROID_REF="${ANDROID_REF:-dev}"
ANDROID_DIR="${ANDROID_DIR:-$HOME/sing-box-for-android}"

rm -rf "$DEST"
git clone -b "${SB_REF}" --recurse-submodules --filter=blob:none \
  "${SB_CLONE_URL:-https://github.com/${SB_REPO}.git}" "$DEST"

cd "$DEST"

if [ -n "${MERGE_TAG:-}" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git remote add upstream "https://github.com/${UPSTREAM_REPO:-SagerNet/sing-box}.git"
  git fetch upstream "refs/tags/${MERGE_TAG}:refs/tags/${MERGE_TAG}"

  BEFORE="$(git rev-parse HEAD)"
  git reset --hard "${MERGE_TAG}"

  if [ ! -f "$OVERLAY_LIST" ]; then
    echo "overlay list not found: $OVERLAY_LIST" >&2
    exit 1
  fi

  overlay_count=0
  while IFS= read -r f || [ -n "$f" ]; do
    case "$f" in '' | \#*) continue ;; esac
    if ! git cat-file -e "${BEFORE}:$f" 2>/dev/null; then
      echo "overlay path missing on ${SB_REF} (${BEFORE:0:8}): $f" >&2
      exit 1
    fi
    git checkout "${BEFORE}" -- "$f"
    overlay_count=$((overlay_count + 1))
  done < "$OVERLAY_LIST"

  if [ "$overlay_count" -eq 0 ]; then
    echo "overlay list is empty: $OVERLAY_LIST" >&2
    exit 1
  fi

  git add -A
  if [ -n "$(git status --porcelain)" ]; then
    git commit --no-edit -m "overlay ${overlay_count} own file(s) onto ${MERGE_TAG}"
  fi
  echo "overlaid ${overlay_count} file(s) from ${SB_REF} onto ${MERGE_TAG}"

  git submodule update --init --recursive
fi

rm -rf "$ANDROID_DIR"
git clone --depth 1 -b "${ANDROID_REF}" \
  "https://github.com/${ANDROID_REPO}.git" "$ANDROID_DIR"
echo "android client: ${ANDROID_REPO}@${ANDROID_REF} -> ${ANDROID_DIR}"

git describe --tags
