/// 发布标识；测试将版本与 pubspec.yaml 对照，避免各网络入口版本漂移。
const appVersion = '1.2.7';
const appUserAgent = 'BangumiFlutter/$appVersion';
const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36 $appUserAgent';
