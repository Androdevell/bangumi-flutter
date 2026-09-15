# Bangumi Flutter

面向 Android 11+（API 30）和 Windows 的第三方 Bangumi 客户端，使用 Flutter 构建。

## 功能

- 每日放送、条目浏览、搜索和完整条目详情
- 时间线、超展开、用户资料、收藏、人物和章节评论
- Bangumi OAuth 登录、Token 自动刷新和系统安全存储
- 收藏状态、观看进度、好友与表情反应操作
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

## OAuth 配置

登录功能需要先在 Bangumi 注册 OAuth 应用，回调地址设置为：

```text
http://localhost/callback
```

运行时通过 `dart-define` 注入应用凭据。不要把真实凭据提交到仓库：

```powershell
flutter run -d windows `
  --dart-define=BGM_OAUTH_APP_ID=your_app_id `
  --dart-define=BGM_OAUTH_APP_SECRET=your_app_secret
```

连接 Android 设备后：

```powershell
flutter devices
flutter run -d <device-id> `
  --dart-define=BGM_OAUTH_APP_ID=your_app_id `
  --dart-define=BGM_OAUTH_APP_SECRET=your_app_secret
```

Cookie 和 Token 保存在 Android/Windows 系统安全存储中，密码不会持久化。

## 网络

默认使用 `https://next.bgm.tv/p1/` API。Android 使用原生 OkHttp 网络桥，Windows 使用 WinHTTP 并读取系统代理、PAC/WPAD。

可在构建时覆盖 API 根地址：

```powershell
flutter run -d windows `
  --dart-define=BGM_API_BASE_URL=https://your-compatible-api.example/
```

## 构建

```powershell
flutter build apk --release --target-platform android-arm64
flutter build windows --release
```

生成位置：

- Android：`build/app/outputs/flutter-apk/`
- Windows：`build/windows/x64/runner/Release/`

本项目是非官方第三方客户端，与 Bangumi 官方无隶属关系。
