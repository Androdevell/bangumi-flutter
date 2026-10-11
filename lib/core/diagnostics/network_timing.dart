import 'package:flutter/foundation.dart';

/// 仅显式诊断构建输出聚合阶段耗时，不输出 URL、账号、正文或凭据。
abstract final class NetworkTiming {
  static const enabled = bool.fromEnvironment('NETWORK_DIAGNOSTICS');
  static void record(String phase, Stopwatch watch) {
    if (enabled) {
      debugPrint(
        'BangumiPerf phase=$phase elapsedMs=${watch.elapsedMilliseconds}',
      );
    }
  }
}
