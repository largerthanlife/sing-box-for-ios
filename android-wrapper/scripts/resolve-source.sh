#!/usr/bin/env bash
# resolve-source.sh <sing_box_repo> <sing_box_ref> <tag_name> [merge_tag]
set -euo pipefail

SB_REPO="${1:-largerthanlife/sing-box}"
SB_REF="${2:-}"
TAG_NAME="${3:-}"
MERGE_TAG="${4:-}"

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

if [ -n "$MERGE_TAG" ] && [[ ! "$MERGE_TAG" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "invalid merge tag: '${MERGE_TAG}'" >&2
  exit 1
fi

export SB_REPO SB_REF MERGE_TAG
echo "resolved sing-box source: ${SB_REPO}@${SB_REF}${MERGE_TAG:+ (merge ${MERGE_TAG})}"
