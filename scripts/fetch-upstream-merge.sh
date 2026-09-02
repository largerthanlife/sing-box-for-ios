#!/usr/bin/env bash
# fetch-upstream-merge.sh — 从已添加的 upstream remote 取 MERGE_TAG 并 reset --hard
#
# MERGE_TAG 可以是上游 tag（例 v1.14.0，自动构建走这条）或分支（例 testing）。
# 先试 refs/tags/${MERGE_TAG}，再试 refs/heads/${MERGE_TAG}。
# reset 目标用完整 ref：clone 已在本地分支 testing 上时，git reset --hard testing
# 会停在 fork 自己的 testing，而不是上游。
#
# 调用方须：cwd 为 clone 工作区，且 remote `upstream` 已存在。
#   BEFORE="$(git rev-parse HEAD)"   # 必须在本函数之前，overlay 要从 fork tip 取文件
#   fetch_upstream_merge_and_reset "$MERGE_TAG"

# 成功后设置 MERGE_REF_KIND=tag|branch，供 apple 配对使用。
MERGE_REF_KIND=""

fetch_upstream_merge_and_reset() {
  local merge_ref="${1:?missing merge ref}"
  MERGE_REF_KIND=""

  if git ls-remote --exit-code upstream "refs/tags/${merge_ref}" >/dev/null 2>&1; then
    git fetch upstream "refs/tags/${merge_ref}:refs/tags/${merge_ref}"
    echo "fetched upstream tag ${merge_ref}"
    git reset --hard "refs/tags/${merge_ref}"
    MERGE_REF_KIND=tag
    return 0
  fi

  # 允许 MERGE_TAG=1.14.0（无 v 前缀）
  if [[ "$merge_ref" != v* ]] && [[ "$merge_ref" == [0-9]* ]]; then
    if git ls-remote --exit-code upstream "refs/tags/v${merge_ref}" >/dev/null 2>&1; then
      git fetch upstream "refs/tags/v${merge_ref}:refs/tags/v${merge_ref}"
      echo "fetched upstream tag v${merge_ref}"
      git reset --hard "refs/tags/v${merge_ref}"
      MERGE_REF_KIND=tag
      return 0
    fi
  fi

  # blob:none：分支历史比单 tag 大得多；checkout 时再按需取 blob。
  if git ls-remote --exit-code upstream "refs/heads/${merge_ref}" >/dev/null 2>&1; then
    git fetch --filter=blob:none upstream "+refs/heads/${merge_ref}:refs/remotes/upstream/${merge_ref}"
    echo "fetched upstream branch ${merge_ref}"
    git reset --hard "refs/remotes/upstream/${merge_ref}"
    MERGE_REF_KIND=branch
    return 0
  fi

  echo "MERGE_TAG '${merge_ref}' is neither a tag nor a branch on upstream" >&2
  return 1
}
