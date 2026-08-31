#!/usr/bin/env bash
# check-auto-build.sh — 对照上游最近 release，看本仓库是否缺 tipa / apk
#
# 用法：
#   check-auto-build.sh tipa|apk
#
# 策略：
#   1) 上游「最新」一条：本仓库无对应 Release，或缺本平台产物 → 编
#   2) 再往前 LOOKBACK-1 条：仅当本仓库已有 Release 但缺本平台产物时补编
#      （避免突然给从未跟过的老稳定版开新 Release）
#
# 环境变量：
#   GH_TOKEN / GITHUB_TOKEN  必需
#   GITHUB_REPOSITORY        必需（owner/repo）
#   UPSTREAM_REPO            可选，默认 SagerNet/sing-box
#   LOOKBACK                 可选，检查上游最近几个 release，默认 5
#   MAX_BUILD                可选，单次最多编几个缺件版本，默认 2
#   GITHUB_OUTPUT            若设置则写入 Actions outputs
set -euo pipefail

KIND="${1:-}"
case "$KIND" in
  tipa) EXT_REGEX='\.tipa$' ;;
  apk)  EXT_REGEX='\.apk$' ;;
  *)
    echo "usage: $0 tipa|apk" >&2
    exit 2
    ;;
esac

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
REPO="${GITHUB_REPOSITORY:-}"
UPSTREAM_REPO="${UPSTREAM_REPO:-SagerNet/sing-box}"
LOOKBACK="${LOOKBACK:-5}"
MAX_BUILD="${MAX_BUILD:-2}"

if [ -z "$TOKEN" ] || [ -z "$REPO" ]; then
  echo "GH_TOKEN/GITHUB_TOKEN and GITHUB_REPOSITORY are required" >&2
  exit 1
fi

auth=(-H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json")

UPSTREAM_JSON=$(curl -fsSL "${auth[@]}" \
  "https://api.github.com/repos/${UPSTREAM_REPO}/releases?per_page=${LOOKBACK}")

INCLUDE_JSON='[]'
count=0
idx=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  TAG=$(printf '%s' "$row" | jq -r '.tag')
  PRE=$(printf '%s' "$row" | jq -r '.prerelease')
  [ -n "$TAG" ] && [ "$TAG" != "null" ] || continue

  REL_CODE=$(curl -s -o /tmp/auto-rel-"${TAG}".json -w '%{http_code}' "${auth[@]}" \
    "https://api.github.com/repos/${REPO}/releases/tags/v${TAG}")
  REL_JSON=""
  if [ "$REL_CODE" = "200" ]; then
    REL_JSON=$(cat /tmp/auto-rel-"${TAG}".json)
  fi

  need=false
  reason=""
  if [ "$REL_CODE" = "404" ]; then
    if [ "$idx" -eq 0 ]; then
      need=true
      reason="no release (latest upstream)"
    else
      reason="no release (skip older; not latest)"
    fi
  elif [ "$REL_CODE" = "200" ]; then
    has=$(printf '%s' "$REL_JSON" | jq -r --arg re "$EXT_REGEX" \
      '[.assets[]?.name | select(test($re))] | length')
    if [ "${has:-0}" -eq 0 ]; then
      need=true
      reason="release exists, missing ${KIND}"
    else
      reason="has ${KIND} (x${has})"
    fi
  else
    echo "unexpected status for v${TAG}: HTTP ${REL_CODE}" >&2
    exit 1
  fi

  echo "upstream=v${TAG} prerelease=${PRE} -> ${reason}"

  if [ "$need" = true ]; then
    if [ "$count" -ge "$MAX_BUILD" ]; then
      echo "skip v${TAG}: already queued ${MAX_BUILD} build(s) this run"
    else
      INCLUDE_JSON=$(printf '%s' "$INCLUDE_JSON" | jq -c \
        --arg tag "$TAG" --arg pre "$PRE" \
        '. + [{tag:$tag, prerelease:$pre}]')
      count=$((count + 1))
    fi
  fi
  idx=$((idx + 1))
done < <(printf '%s' "$UPSTREAM_JSON" | jq -c '
  .[] | {tag:(.tag_name | ltrimstr("v")), prerelease:(.prerelease|tostring)}
')

if [ "$count" -gt 0 ]; then
  SHOULD=true
else
  SHOULD=false
fi
MATRIX=$(jq -nc --argjson inc "$INCLUDE_JSON" '{include:$inc}')

echo "should_build=${SHOULD}"
echo "matrix=${MATRIX}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "should_build=${SHOULD}"
    echo "matrix=${MATRIX}"
  } >> "$GITHUB_OUTPUT"
fi
