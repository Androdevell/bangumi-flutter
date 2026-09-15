import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class RefreshRateProbe extends StatefulWidget {
  const RefreshRateProbe({super.key});

  static const enabled = bool.fromEnvironment('SHOW_REFRESH_DIAGNOSTICS');

  @override
  State<RefreshRateProbe> createState() => _RefreshRateProbeState();
}

class _RefreshRateProbeState extends State<RefreshRateProbe> {
  static const _channel = MethodChannel('bangumi_flutter/display');

  final Stopwatch _sampleWatch = Stopwatch();
  Timer? _timer;
  int _frames = 0;
  double _fps = 0;
  double _currentHz = 0;
  double _requestedHz = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _sampleWatch.start();
    _requestHighestRate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    _frames += timings.length;
  }

  Future<void> _requestHighestRate() async {
    try {
      await _channel.invokeMethod<void>('requestHighestRefreshRate');
    } on PlatformException {
      // The Android bridge is unavailable on Windows.
    } on MissingPluginException {
      // The Android bridge is unavailable on Windows.
    }
  }

  Future<void> _sample() async {
    final elapsedSeconds = _sampleWatch.elapsedMicroseconds / 1000000;
    final sampledFps = elapsedSeconds == 0 ? 0.0 : _frames / elapsedSeconds;
    _frames = 0;
    _sampleWatch
      ..reset()
      ..start();

    Map<String, dynamic>? info;
    try {
      info = await _channel.invokeMapMethod<String, dynamic>('getDisplayInfo');
    } on PlatformException {
      // Keep zero values when the Android bridge is unavailable.
    } on MissingPluginException {
      // Keep zero values when the Android bridge is unavailable.
    }

    if (!mounted) return;
    setState(() {
      _fps = sampledFps;
      _currentHz = (info?['currentRefreshRate'] as num?)?.toDouble() ?? 0;
      _requestedHz = (info?['requestedRefreshRate'] as num?)?.toDouble() ?? 0;
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      right: 8,
      child: IgnorePointer(
        child: Material(
          color: const Color(0xdd101318),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(
              'FPS ${_fps.toStringAsFixed(0)}  '
              'Hz ${_currentHz.toStringAsFixed(0)}  '
              '请求 ${_requestedHz.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xff58f6a9),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
