#!/usr/bin/env bash
# resolve-source.sh <sing_box_repo> <sing_box_ref> <tag_name>
#
# 解析本次构建使用的 sing-box 源码来源，导出两个变量：
#   SB_REPO  GitHub 仓库 (owner/repo)，默认 SagerNet/sing-box
#   SB_REF   要 clone 的分支或 tag；留空时回退为 v<tag_name>
set -euo pipefail

SB_REPO="${1:-SagerNet/sing-box}"
SB_REF="${2:-}"
TAG_NAME="${3:-}"

if [[ ! "$SB_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "invalid sing_box_repo: '${SB_REPO}' (expect owner/repo)" >&2
  exit 1
fi

if [ -z "$SB_REF" ]; then
  if [ -z "$TAG_NAME" ]; then
    echo "tag_name is required when sing_box_ref is empty" >&2
    exit 1
  fi
  SB_REF="v${TAG_NAME}"
fi

export SB_REPO SB_REF
echo "resolved sing-box source: ${SB_REPO}@${SB_REF}"
