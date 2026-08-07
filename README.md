# actions

通过 GitHub Actions 自动编译 sing-box iOS (TrollStore `.tipa`) 安装包。

## 构建上游原版

Actions → **Build sing-box-for-ios** → 填入 `tag_name`（如 `1.13.16`）→ Run workflow。

## 构建自己修改过的 sing-box

1. Fork [SagerNet/sing-box](https://github.com/SagerNet/sing-box)，在 fork 里修改源码并 push（分支或 tag 均可）。
2. Actions → **Build sing-box-for-ios** → Run workflow，填写：
   - `tag_name`：发布用的版本号（release tag 与 `.tipa` 文件名，例：`1.14.0-beta.8-custom.1`）
   - `sing_box_repo`：你的 fork，例：`yourname/sing-box`
   - `sing_box_ref`：你的分支或 tag，例：`testing`（留空则使用 `v<tag_name>`）
3. 构建完成后在 Releases 下载 `sing-box-<tag_name>.tipa`。

注意：App 内嵌的版本号取自源码仓库的 `git describe --tags`；从分支构建时为 `最近的tag-<短commit>` 形式，因此 clone 不使用 `--depth 1`。

## 脚本测试

`scripts/resolve-source.sh` 负责解析源码仓库/分支，改动后运行：

```bash
bash scripts/test-resolve-source.sh
```
