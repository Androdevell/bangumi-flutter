# Bangumi Flutter

面向 Android 11+（API 30）和 Windows 的第三方 Bangumi 客户端，使用 Flutter 构建。

## 功能

- 每日放送、条目浏览、搜索和完整条目详情
- 浏览/搜索分页与筛选重置，搜索防抖与短期缓存
- 时间线、超展开、用户资料、收藏、人物和章节评论
- Bangumi OAuth 登录、Token 自动刷新和系统安全存储
- 收藏状态、观看进度、好友与表情反应操作
- Bangumi 站内图片表情、贴贴和超展开讨论详情
- GitHub Releases 新版本检测
- Android 高刷新率支持，以及封面、头像和预览图片磁盘缓存
- Android 原生网络兼容层和 Windows WinHTTP 系统代理支持

## 环境

- Flutter 3.29 或更高版本
- Android SDK，最低 API 30
- Visual Studio 2022 Desktop development with C++（Windows 构建）

```powershell
flutter pub get
flutter analyze
flutter test
```

## 发布版本

每次发布前先更新 `pubspec.yaml` 中的 `version`。格式为 `主版本.次版本.修订号+构建号`，例如 `1.1.0+2`；随后使用相同版本创建 `v1.1.0` Git 标签和 GitHub Release。应用内“检查更新”以 GitHub 最新 Release 为准。

注意：实际已发布的 1.1.4 APK 构建号为 **2006**（以前命令行覆盖了源码中的构建号）。
从 `1.1.7+2009` 起在 `pubspec.yaml` 中统一保存真实构建号，后续每次发布继续递增，
不使用较小的 `+8/+9`，也不通过命令行另行覆盖版本。

## 网络

默认使用 `https://next.bgm.tv/p1/` API。Android 使用原生 OkHttp 网络桥，Windows 使用 WinHTTP 并读取系统代理、PAC/WPAD。

可在构建时覆盖 API 根地址：

```powershell
flutter run -d windows `
  --dart-define=BGM_API_BASE_URL=https://your-compatible-api.example/
```

## 构建

### OAuth 与签名

源码不再内置 OAuth 凭据。请先在 Bangumi 开发者后台重置已泄露的旧密钥，
在本机创建已被 Git 忽略的 `oauth-config.json`：

```json
{
  "BGM_OAUTH_APP_ID": "your-application-id",
  "BGM_OAUTH_APP_SECRET": "your-new-application-secret"
}
```

不得提交真实凭据、`android/key.properties` 或签名文件。
CI 构建时应从加密 Secrets 注入，不要输出密钥或将配置文件作为构建产物上传。
移动/桌面客户端中的构建参数仍可从二进制提取，并非保密边界；
若需要真正保密，必须改用服务端 OAuth 令牌交换。
不提供 OAuth 参数仍可运行浏览功能，登录入口会明确提示配置缺失。

Android Release 必须提供 `android/key.properties` 的 `storeFile`、`storePassword`、
`keyAlias`、`keyPassword`，且签名文件必须存在；缺失时拒绝构建，不回退 debug 签名。
继续使用原正式密钥，以确保旧用户可覆盖安装。

正式发行推荐使用带预检的双平台脚本：

```powershell
./tool/release.ps1 -OAuthConfig ./oauth-config.json -PreviousApk ./downloaded-last-release.apk
```

亦可在本地进程或 CI Secrets 中设置 `BGM_OAUTH_APP_ID`、`BGM_OAUTH_APP_SECRET` 后省略 `-OAuthConfig`。
脚本不输出凭据，校验构建号严格高于基准 APK，校验签名相同、最终 Android/Windows 版本、
arm64-v8a 架构并打包完整 Windows 目录。仅预检时加 `-ValidateOnly`。
Android 正式构建还会强制检查完整 OAuth 参数及已发布构建号下界；不能把未配置登录的包当作正式发行。
本次 1.1.7 依用户要求使用既有配置生成可登录的正式发行包；公开客户端中的 Secret 不构成保密边界，仍建议尽快轮换。

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=oauth-config.json
flutter build windows --release --dart-define-from-file=oauth-config.json
```

生成位置：

- Android：`build/app/outputs/flutter-apk/`
- Windows：`build/windows/x64/runner/Release/`

Windows 需要分发整个 Release 文件夹，不能只复制 exe。

## 1.1.6 修复与验收

本次版本 `1.1.6+8` 对应 P1 清单的 16 项修复，详见 [修复验收记录](P1-修复验收.md)。
GET 使用五分钟缓存和相同请求合并，并发不超过三；手动刷新、写操作和登录变化会使缓存失效。
429 尊重 `Retry-After`，超过十秒的限流直接提示，不提前重试；写操作不自动重试。
搜索防抖 350ms、缓存两分钟，浏览/搜索通过滚动或“加载更多”翻页；
时间线、超展开和其他列表本次仍使用原有单次请求上限，未宣称全站分页。
正式更新渠道忽略预发布，在语义版本优先级相同时额外比较本项目纯数字 `+build`。
图片内存缓存上限 64 MiB，磁盘缓存保留十四天、最多六百个缓存对象；
Android 图片传输采用临时文件流，不再整张图片通过 MethodChannel 复制。

之前的 1.1.5/1.1.6 未配置 OAuth 构建仅用于浏览验证，没有上传正式 Release。
现在正式 Release 强制配置 OAuth；源码推送仍不自动改变应用内的最新 Release，需上传带版本标签的正式产物。

## 安全与隐私修复

1.1.5 改用系统 DNS 后，在解析受干扰的网络上产生了 Android 直连回归。
1.1.8 为本站六个域名增加限时 HTTPS DNS 查询（每个解析器最多两秒）和 TTL 缓存；
查询失败时使用已核对的多地址应急路由，三十秒后重试加密解析。
备用 CDN 地址不是永久解析结果，未来路由变化仍可能需要更新版本；不能保证在所有运营商网络上都可直连。
非本站域名仍使用系统 DNS，保留仅针对 Bangumi 域名的 TLS 分片兼容与正常证书校验。
加密解析仅提交域名和 A 记录类型，不提交账户、Cookie 或 OAuth 凭据。
协议参考：[Cloudflare DoH JSON 文档](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/)。
连接失败只记录域名及异常类别，不记录 URL 查询参数、请求内容或凭据。
Android 关闭自动备份，单独排除安全存储的云备份与设备迁移；
Keystore 不可用时不再静默删除密文，新设备需重新登录。
豆瓣剧照预览已停用，不再向豆瓣发送浏览的条目标题。

安全回归检查通过 GitHub Actions 执行：依赖解析、静态分析、单元/widget 测试与覆盖率生成。
真实网络测试默认跳过，不会在 CI 使用真实账户。

规则依据：[Android 自动备份说明](https://developer.android.com/identity/data/autobackup)、
[OkHttp 多地址连接说明](https://github.com/square/okhttp/blob/master/README.md)。

本项目是非官方第三方客户端，与 Bangumi 官方无隶属关系。
