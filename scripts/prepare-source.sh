#!/usr/bin/env bash
# prepare-source.sh — clone sing-box 源码并准备到可编译状态（纯 git 操作，跨平台）
#
# 环境变量：
#   SB_REPO        (必需) sing-box 源码仓库 (owner/repo)
#   SB_REF         (必需) 要 clone 的分支或 tag
#   SB_CLONE_URL   (可选) 完整 clone URL（私有仓库内嵌 token），默认按 SB_REPO 拼匿名 URL
#   MERGE_TAG      (可选) 用该上游 tag 的完整文件树替换工作区，再叠回自有文件
#   UPSTREAM_REPO  (可选) MERGE_TAG 的来源仓库，默认 SagerNet/sing-box
#   OVERLAY_LIST   (可选) 自有文件清单路径（每行一个相对路径，# 开头为注释）
#                         默认：本脚本同目录下的 overlay-files.txt
#   UPDATE_APPLE   (可选) "true" 时用 sing-box-for-apple 最新 main 替换 submodule 指针
#   PREPARE_DIR    (可选) 输出目录，默认 $HOME/sing-box
#
# 合入策略（为何不用 git merge）：
#   上游 testing 会被 rebase/force-push，merge 会产生假冲突；即便 -X theirs +
#   处理 modify/delete，两边改了同一文件不同行时仍会拼出编不过的半成品
#   （beta.14：dhcp.go 重复声明、local.go 残留无用 import）。
#   正确语义是「上游 tag 的完整树 + 明确列出的自有新增文件」，因此：
#   reset --hard 到 MERGE_TAG，再从原分支 tip 检出 OVERLAY_LIST 中的路径。
#
# 顺序约束：先 overlay（其后的 submodule update 会按 gitlink 重置 clients/apple），
# 再执行 UPDATE_APPLE 替换，否则替换结果会被 submodule update 覆盖。
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}"
DEST="${PREPARE_DIR:-$HOME/sing-box}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY_LIST="${OVERLAY_LIST:-$SCRIPT_DIR/overlay-files.txt}"

rm -rf "$DEST"
# 不用 --depth 1：libbox 通过 git describe --tags 内嵌版本号，需要完整 tag 历史
git clone -b "${SB_REF}" --recurse-submodules --filter=blob:none "${SB_CLONE_URL:-https://github.com/${SB_REPO}.git}" "$DEST"

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

if [ "${UPDATE_APPLE:-false}" = "true" ]; then
  rm -rf clients/apple
  git clone --recurse-submodules --depth 1 https://github.com/SagerNet/sing-box-for-apple.git clients/apple
fi

git describe --tags
