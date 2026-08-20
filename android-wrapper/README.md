# actions

通过 GitHub Actions 编译 **sing-box Android 图形客户端** APK（旁加载 / ChromeOS 可用）。

与 [sing-box-for-ios](https://github.com/largerthanlife/sing-box-for-ios) 同思路：

1. 克隆 `largerthanlife/sing-box`（默认 `testing`）
2. 可选：重置到上游 tag，再叠回 `scripts/overlay-files.txt` 里的自有文件（如 chacha20）
3. 克隆 `SagerNet/sing-box-for-android`
4. `gomobile` 编 `libbox*.aar` → 拷进 Android 工程
5. Gradle 打 APK 并上传 Release

> Windows 桌面客户端不在本仓库范围；ChromeOS 一般直接装这份 Android APK。

## 手动构建

Actions → **Build sing-box-for-android** → Run workflow：

| 参数 | 说明 | 默认 |
|---|---|---|
| `tag_name` | 发布版本号 / APK 文件名用 | 必填 |
| `sing_box_repo` | 核心源码仓库 | `largerthanlife/sing-box` |
| `sing_box_ref` | 分支或 tag；留空则 `v<tag_name>` | 空 |
| `upstream_tag` | 可选：上游 tag 做底 + overlay | 空 |
| `android_ref` | Android 客户端分支 | `dev` |
| `prerelease` | 是否 prerelease | `true` |
| `build_variant` | `debug`（旁加载，无需自备签名）或 `release`（需 Secrets 签名） | `debug` |

建议调试参数：`sing_box_ref=testing`，`upstream_tag=v1.14.0-beta.17`，`build_variant=debug`。

## Release 签名（可选）

`build_variant=release` 时需要仓库 Secrets（与官方 Gradle 一致）：

- `LOCAL_PROPERTIES`：Base64 编码的 `local.properties`，内含 `KEYSTORE_PASS` / `ALIAS_NAME` / `ALIAS_PASS`
- 并把 `release.keystore` 放到构建流程可访问处（见 workflow 注释）

旁加载用 **debug** 即可，ChromeOS / 普通 Android 都能装。

## 自有 core 改动

与 iOS 包装相同：在 [largerthanlife/sing-box](https://github.com/largerthanlife/sing-box) **新增文件**，路径写入本仓库 `scripts/overlay-files.txt`。
