# actions

通过 GitHub Actions 自动编译 sing-box iOS (TrollStore `.tipa`) 安装包。

## 自动跟随上游发版（Auto build on upstream release）

每 6 小时检查一次 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 最近若干 release（含 beta）。需要补产物时自动：

1. 克隆 `largerthanlife/sing-box` 的 `testing` 分支
2. 将工作区重置为上游对应 tag 的完整文件树，再叠回 `scripts/overlay-files.txt` 列出的自有文件
3. 用与 overlay 目标同代的 sing-box-for-apple：发版 tag 配「Bump version x.y.z」，`testing` 等分支配 apple `main`（不要拿过新的 main 去配冻结的 Libbox tag）
4. 编译并在 Releases 发布产物，上游是测试版则标记为 prerelease

iOS（`.tipa`）与 Android（`.apk`）各一个 workflow，**共用同一 Release tag**，缺哪边补哪边：
- 上游最新：本仓库无 Release，或有 Release 缺对应产物 → 会编
- 更早版本：仅当本仓库**已有** Release 却缺 tipa/apk 时补编（避免给从没跟过的老版本突然开新 Release）

也可以手动 Run workflow（可选填别的分支）。

注意：

- **fork 的定时任务**需要在 Actions 页面启用过 workflow 才会运行；仓库约 60 天无活动会被 GitHub 自动暂停，回页面重新启用即可。
- **不要用 git merge 追上游**：上游 testing 会被 rebase，merge（即便 `-X theirs`）仍可能把两边改动拼成编不过的半成品。当前策略是「上游 tag 或分支原样 + 清单内自有文件」。
- **自有改动必须是新增文件**，并把路径写进 `scripts/overlay-files.txt`。对上游已有文件的修改不会被带上（方法注册请走 `init()`，不要依赖改 option enum）。
- 自定义分支不叫 `testing` 的话，改 `auto-build.yml` 里 `SB_REF` 的默认值。

## Android APK（Build sing-box-for-android）

同一仓库也可编 Android 图形客户端 APK（旁加载 / Chromebook）：

Actions → **Build sing-box-for-android** → Run workflow。

| 参数 | 说明 | 默认 |
|---|---|---|
| `tag_name` | 发布版本号 | 必填 |
| `sing_box_ref` | 例 `testing` | 空则 `v<tag_name>` |
| `upstream_tag` | 上游 tag 或分支做底 + overlay（例 `v1.14.0` / `testing`） | 空 |
| `build_variant` | `debug`（推荐旁加载）或 `release` | `debug` |

默认只上传两个分架构包（各约 60–70MB，不再传 150MB+ universal）：

| 文件名含 | 装哪里 |
|---|---|
| `arm64-v8a` | 手机、ARM Chromebook |
| `x86_64` | Intel / AMD Chromebook |

不需要 Android 5 的 `legacy` 包；若要改 ABI / 加 universal / legacy，可在 workflow 里设环境变量 `APK_ABIS`、`APK_INCLUDE_UNIVERSAL`、`APK_INCLUDE_LEGACY`。

自有 core 文件仍写在 `scripts/overlay-files.txt`。定时任务见 **Auto build on upstream release**（Android 版 workflow：`auto-build-android.yml`）。

---

## 手动构建（Build sing-box-for-ios）

Actions → **Build sing-box-for-ios** → Run workflow：

| 参数 | 说明 | 默认 |
|---|---|---|
| `tag_name` | 发布版本号（release tag 与 `.tipa` 文件名），例 `1.14.0-beta.8-custom.1` | 必填 |
| `sing_box_repo` | sing-box 源码仓库 | `largerthanlife/sing-box` |
| `sing_box_ref` | fork 上带 overlay 文件的分支或 tag；留空则 `v<tag_name>` | `testing` |
| `upstream_tag` | 上游 tag 或分支做底再叠 overlay。默认 `testing`（当前官方最新）；自动构建用 `v1.14.0` 这类发版 tag | `testing` |
| `prerelease` | 是否发布为测试版 | `false` |
| `update_apple` | 拉取与 overlay 目标同代的 apple 客户端（分支→`main`，发版 tag→对应 `Bump version`） | `true` |
| `run_build` / `run_build_reF1nd` | 是否编译 原版 / reF1nd 版 | `true` |

改源码的流程：在 [largerthanlife/sing-box](https://github.com/largerthanlife/sing-box) 以**新增文件**方式改并 push → 若是新文件，把路径加进本仓库 `scripts/overlay-files.txt` → 手动触发或等上游发版自动出包。

App 内嵌版本号取自源码仓库的 `git describe --tags`；从分支构建时为 `最近的tag-<短commit>` 形式，因此 clone 不使用 `--depth 1`。

## 脚本

- `scripts/resolve-source.sh <repo> <ref> <tag_name> [merge_tag]`：解析/校验源码来源，导出 `SB_REPO` / `SB_REF` / `MERGE_TAG`（`merge_tag` 可以是 tag 或分支名）
- `scripts/overlay-files.txt`：叠到上游 tag/分支上的自有文件清单
- `scripts/prepare-source.sh`：clone → 可选 reset 到上游 tag 或分支并 overlay → 可选按目标代际替换 apple 客户端 → 打 apple 小补丁
- `scripts/fetch-upstream-merge.sh`：`MERGE_TAG` 先按 tag 再按分支从 SagerNet/sing-box fetch，再 `reset --hard`
- `scripts/pair-apple.sh`：`UPDATE_APPLE=true` 时分支配 apple `main`，发版 tag 配 `Bump version <x.y.z>`，禁止用过新的 main 配冻结 tag
- `scripts/apple-patches/`：tipa 构建前对 `clients/apple` 的补丁（不改 sing-box 源码）
- `scripts/check-auto-build.sh`：自动发版前检查本仓库是否缺 tipa/apk
- `scripts/build-tipa.sh`：环境变量驱动的完整构建（prepare-source → gomobile → xcodebuild → ldid → tipa）。会签署 Share/Action 等扩展，否则系统分享里的「Send with Taildrop」点了无反应。

改动 `scripts/**` 后 CI（Test scripts）会自动运行测试样例，本地也可执行：

```bash
bash scripts/test-resolve-source.sh
bash scripts/test-fetch-upstream-merge.sh
bash scripts/test-pair-apple.sh
bash scripts/test-prepare-source.sh
bash scripts/test-apple-patches.sh
bash scripts/test-check-auto-build.sh
```
