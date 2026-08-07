#!/usr/bin/env bash
# prepare-source.sh — clone sing-box 源码并准备到可编译状态（纯 git 操作，跨平台）
#
# 环境变量：
#   SB_REPO        (必需) sing-box 源码仓库 (owner/repo)
#   SB_REF         (必需) 要 clone 的分支或 tag
#   SB_CLONE_URL   (可选) 完整 clone URL（私有仓库内嵌 token），默认按 SB_REPO 拼匿名 URL
#   MERGE_TAG      (可选) clone 后合入的上游 tag，例 v1.14.0-beta.9
#   UPSTREAM_REPO  (可选) MERGE_TAG 的来源仓库，默认 SagerNet/sing-box
#   UPDATE_APPLE   (可选) "true" 时用 sing-box-for-apple 最新 main 替换 submodule 指针
#                         指定的旧版本（上游发版时 gitlink 可能滞后于 libbox API）
#   PREPARE_DIR    (可选) 输出目录，默认 $HOME/sing-box
#
# 顺序约束：先 merge（其后的 submodule update 会按 gitlink 重置 clients/apple），
# 再执行 UPDATE_APPLE 替换，否则替换结果会被 submodule update 覆盖。
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}"
DEST="${PREPARE_DIR:-$HOME/sing-box}"

rm -rf "$DEST"
# 不用 --depth 1：libbox 通过 git describe --tags 内嵌版本号，需要完整 tag 历史
git clone -b "${SB_REF}" --recurse-submodules --filter=blob:none "${SB_CLONE_URL:-https://github.com/${SB_REPO}.git}" "$DEST"

cd "$DEST"

if [ -n "${MERGE_TAG:-}" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git remote add upstream "https://github.com/${UPSTREAM_REPO:-SagerNet/sing-box}.git"
  git fetch upstream "refs/tags/${MERGE_TAG}:refs/tags/${MERGE_TAG}"
  git merge --no-edit "${MERGE_TAG}"
  git submodule update --init --recursive
fi

if [ "${UPDATE_APPLE:-false}" = "true" ]; then
  rm -rf clients/apple
  git clone --recurse-submodules --depth 1 https://github.com/SagerNet/sing-box-for-apple.git clients/apple
fi

git describe --tags
