# Bangumi Flutter

<img src="assets/branding/app_icon_anime.png" width="80" alt="Bangumi Flutter 图标">

面向 Android 11+ 与 Windows 的非官方 Bangumi 客户端。

[下载最新版](https://github.com/Androdevell/bangumi-flutter/releases/latest) · [更新记录](CHANGELOG.md)

Android 下载 **arm64-v8a APK**。Windows 请解压完整 ZIP，再运行 `windows-x64/bangumi_flutter.exe`，不要单独移动 EXE。覆盖安装请保留应用数据。

## 界面

Windows 1.2.11 直连模式实拍（2026-10-22）：

![Windows 首页：每日放送与作品卡片](docs/screenshots/windows-home-1.2.11.jpg)

## 功能

- 每日放送、搜索、类型筛选、分页与详情；标签可点击进入精确筛选。
- 收藏、章节进度、时间线、超展开、小组、用户资料及评论回复。
- 打开 Bangumi 站内链接；支持粘贴、Android 文本分享及网页链接入口。
- 评论图片、表情与多图查看器；双击、按钮和键盘缩放及复位。
- 中文、英文、日文；传统/二次元图标、动态取色与自定义主题。
- 应用内更新说明、下载、摘要验证；登录凭据使用系统加密存储。

## 网络与隐私

默认 API 为 `https://next.bgm.tv/p1/`。Windows 默认跟随系统代理；可在“我的 → 数据与网络”选择直连，重启生效。直连模式不使用代理，本站域名采用有界加密解析及握手兼容，不更改系统代理、hosts 或证书信任。不保证所有运营商均可访问。

站外评论图片默认按需加载，可允许图床或禁止。图片请求不发送 Bangumi Cookie 和 OAuth 凭据，拒绝私网地址、不安全跳转和超限资源。

第三方剧照默认关闭，仅主动开启并访问预览页后查询。豆瓣会收到作品标题、IP 与请求信息；验证、限流、空检索和下架仍会造成不可用。关闭后停止新请求，已发请求无法撤回。本轮未修复第三方检索服务的可用性问题。

公开日历可保存到普通缓存；账号、Cookie、令牌不会迁出加密存储。网页登录失效时可单独验证，无需先退出 OAuth 账号。不要通过卸载或清数据解决普通网络错误。

## 开发与测试

需要项目锁定的 Flutter/Dart SDK、Android SDK，以及 Windows 的 Visual Studio C++ 桌面组件。首次运行 `flutter pub get`。

```powershell
# 迭代：按变更映射选择测试；公共层或未知改动回退全量
./tool/verify.ps1
# 显式定向
./tool/verify.ps1 -Tests test/link_image_tag_test.dart
# 定稿全量
./tool/verify.ps1 -Mode full
```

完整日志与 JSON 摘要保存在 `build/verification/`。外网和真实会话探针默认跳过，不能把跳过计为通过。正式发行脚本仍强制执行分析、完整 Flutter 回归与 Android 原生测试，不接受人工跳过门禁。

## 构建与发布

每次程序发行同时递增 `pubspec.yaml` 的版本名/构建号与 `lib/core/app_identity.dart` 的版本。不得降低真实已发布 APK 的构建号，也不通过命令行覆盖一个更小的值。保持浏览器认证标识稳定。

本地创建被 Git 忽略的 `oauth-config.json`，填写 `BGM_OAUTH_APP_ID` 和 `BGM_OAUTH_APP_SECRET`。Android 还需原正式签名与 `android/key.properties`。不提交或上传这些文件；CI 从加密 Secrets 注入。

```powershell
./tool/release.ps1 -Flutter D:/flutter/bin/flutter.bat `
  -OAuthConfig ./oauth-config.json `
  -PreviousApk ./dist/上一版/bangumi-上一版-arm64-v8a.apk -NoPub
```

脚本校验新旧签名、严格递增构建号、ARM64 架构、双端版本、OAuth 构建配置和图标，输出完整 Windows ZIP 与追溯清单。清单不是独立发行者签名。移动/桌面客户端内置 Secret 可被提取，不能作为服务端保密边界；本轮未更换用户确认沿用的配置。

Release 标题统一 `v版本号`，正文只包含非空的“功能与优化”“修复”，参见 [模板](tool/release-notes-template.md)。验证、限制和构建记录写入实施文档，不堆进 Release。历史说明可通过 `tool/normalize-release-notes.ps1` 预览，`-Apply` 前自动备份；只修改文本，不改旧标签或附件。

当前实施与未完成的设备验收见 [1.2.11 实施记录](链接直连与图片交互及测试发布优化实施记录-1.2.11.md)。

本项目与 Bangumi 官方无隶属关系。
