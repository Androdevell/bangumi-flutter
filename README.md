# Bangumi Flutter

面向 Android 11+（API 30）和 Windows 的第三方 Bangumi 客户端，使用 Flutter 构建。

## 功能

- 每日放送、条目浏览、搜索和完整条目详情
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
