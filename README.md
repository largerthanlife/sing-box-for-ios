# actions

通过 GitHub Actions 自动编译 sing-box iOS (TrollStore `.tipa`) 安装包。

## 自动跟随上游发版（Auto build on upstream release）

每 6 小时检查一次 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 的最新 release（含 beta）。发现新版本时自动：

1. 克隆 `largerthanlife/sing-box` 的 `testing` 分支
2. 在 CI 中把上游新 tag 合入（你的自定义改动因此始终在包里）
3. 用 sing-box-for-apple 最新 main 作为客户端代码（上游发版时其 submodule 指针可能滞后于 libbox API，直接按指针编译会报 `cannot find 'LibboxRedirectStderr' in scope` 之类的错）
4. 编译并在 Releases 发布 `sing-box-<版本号>.tipa`，上游是测试版则标记为 prerelease

已出过的版本自动跳过。也可以手动 Run workflow（可选填别的分支）。

注意：

- **fork 的定时任务**需要在 Actions 页面启用过 workflow 才会运行；仓库约 60 天无活动会被 GitHub 自动暂停，回页面重新启用即可。
- 如果你的自定义改动与上游新版本**冲突**，合入会失败、构建变红且不会出包——在 fork 里手动合并上游解决冲突后，删除对应失败 run 再手动触发一次即可。
- 自定义分支不叫 `testing` 的话，改 `auto-build.yml` 里 `SB_REF` 的默认值。

## 手动构建（Build sing-box-for-ios）

Actions → **Build sing-box-for-ios** → Run workflow：

| 参数 | 说明 | 默认 |
|---|---|---|
| `tag_name` | 发布版本号（release tag 与 `.tipa` 文件名），例 `1.14.0-beta.8-custom.1` | 必填 |
| `sing_box_repo` | sing-box 源码仓库 | `largerthanlife/sing-box` |
| `sing_box_ref` | 分支或 tag，例 `testing`；留空则使用 `v<tag_name>` | 空 |
| `upstream_tag` | 可选：clone 后合入的上游 tag，例 `v1.14.0-beta.9` | 空 |
| `prerelease` | 是否发布为测试版 | `false` |
| `update_apple` | 是否用 sing-box-for-apple 最新 main 替换 submodule 指定的客户端（构建 beta 版本如遇 Swift 编译错误，选 `true`） | `false` |
| `run_build` / `run_build_reF1nd` | 是否编译 原版 / reF1nd 版 | `true` |

改源码的流程：在 [largerthanlife/sing-box](https://github.com/largerthanlife/sing-box) 修改并 push（分支或 tag）→ 用上面的参数手动触发，或等上游发版走自动流程。

App 内嵌版本号取自源码仓库的 `git describe --tags`；从分支构建时为 `最近的tag-<短commit>` 形式，因此 clone 不使用 `--depth 1`。

## 脚本

- `scripts/resolve-source.sh <repo> <ref> <tag_name> [merge_tag]`：解析/校验源码来源，导出 `SB_REPO` / `SB_REF` / `MERGE_TAG`
- `scripts/prepare-source.sh`：clone → 可选合入上游 tag → 可选替换为最新 apple 客户端（纯 git 操作，可本地测试）
- `scripts/build-tipa.sh`：环境变量驱动的完整构建（prepare-source → gomobile → xcodebuild → ldid → tipa）

改动 `scripts/**` 后 CI（Test scripts）会自动运行测试样例，本地也可执行：

```bash
bash scripts/test-resolve-source.sh
```
