#!/usr/bin/env bash
# pair-apple.sh — 按 Libbox 代际挑选 sing-box-for-apple（source 后调用）
#
# 上游 apple 仓库没有跟 sing-box 对齐的 git tag，版本写在 commit message
# 「Bump version 1.14.0」里。配对规则：
#   - overlay / 构建目标是分支（testing）→ apple 仓库默认分支（当前是 dev，
#     含 createAutoRedirect 等与 testing Libbox 同代的协议）
#   - 目标是发版 tag（v1.14.0 / 1.14.0）→ 检出对应 Bump version，不要漂在
#     默认分支 / main 上（对冻结 Libbox 过新）
#
#   apple_version_from_ref <ref>          版本号或空（分支名）
#   clone_paired_apple <dest> <pair_ref> [kind]
#     kind=tag|branch；省略则从 pair_ref 形态推断
#   APPLE_CLONE_URL / APPLE_REPO  可覆盖（测试用）

apple_version_from_ref() {
  local ref="${1:-}"
  case "$ref" in
    v[0-9]* | [0-9]*)
      printf '%s\n' "${ref#v}"
      ;;
    *)
      printf ''
      ;;
  esac
}

_apple_clone_url() {
  printf '%s\n' "${APPLE_CLONE_URL:-https://github.com/${APPLE_REPO:-SagerNet/sing-box-for-apple}.git}"
}

find_apple_bump_commit() {
  local repo_dir="${1:?}" version="${2:?}"
  git -C "$repo_dir" log --all --format=%H --grep="^Bump version ${version}$" -n 1
}

clone_paired_apple() {
  local dest="${1:?missing apple dest}"
  local pair_ref="${2:-}"
  local kind="${3:-}"
  local url
  url="$(_apple_clone_url)"

  rm -rf "$dest"

  local use_default=0
  local ver=""
  case "$kind" in
    branch) use_default=1 ;;
    tag)
      ver="$(apple_version_from_ref "$pair_ref")"
      if [ -z "$ver" ]; then
        echo "apple pair: tag '${pair_ref}' is not a version (v1.14.0 / 1.14.0)" >&2
        return 1
      fi
      ;;
    *)
      ver="$(apple_version_from_ref "$pair_ref")"
      if [ -z "$ver" ]; then
        use_default=1
      fi
      ;;
  esac

  if [ "$use_default" -eq 1 ]; then
    # 不传 -b：跟旧的 working clone 一样，用仓库默认分支（dev，不是 main）
    git clone --recurse-submodules --depth 1 "$url" "$dest"
    echo "apple client: $(git -C "$dest" rev-parse --abbrev-ref HEAD) ($(git -C "$dest" rev-parse --short HEAD); default branch, paired with branch ${pair_ref:-none})"
    return 0
  fi

  # 需要全部分支的 commit 历史才能在 main 上找到 Bump version；blob:none 避免整树下载
  git clone --filter=blob:none "$url" "$dest"

  local sha=""
  sha="$(find_apple_bump_commit "$dest" "$ver")"
  if [ -z "$sha" ] && [ -n "${TAG_NAME:-}" ]; then
    local fallback
    fallback="$(apple_version_from_ref "$TAG_NAME")"
    if [ -n "$fallback" ] && [ "$fallback" != "$ver" ]; then
      sha="$(find_apple_bump_commit "$dest" "$fallback")"
      if [ -n "$sha" ]; then
        echo "apple pair: no bump for '${ver}', falling back to TAG_NAME ${fallback}"
        ver="$fallback"
      fi
    fi
  fi
  if [ -z "$sha" ]; then
    echo "no sing-box-for-apple commit 'Bump version ${ver}' (pair_ref=${pair_ref})" >&2
    echo "refusing to clone floating apple default branch onto a frozen sing-box tag" >&2
    return 1
  fi

  git -C "$dest" config advice.detachedHead false
  git -C "$dest" checkout --force "$sha"
  git -C "$dest" submodule update --init --recursive
  echo "apple client: $(printf '%.8s' "$sha") (Bump version ${ver})"
}
