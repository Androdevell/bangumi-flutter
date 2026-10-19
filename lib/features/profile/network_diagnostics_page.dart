import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/diagnostics/network_diagnostics.dart';
import '../../core/localization/app_localizations.dart';
import '../../widgets/common.dart';

class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});
  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  NetworkDiagnosticsService? _service;
  final Map<String, List<ComposeNetworkSample>> _samples = {};
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    _service?.close();
    final service = _service = NetworkDiagnosticsService();
    final budget = Stopwatch()..start();
    setState(() {
      _busy = true;
      _samples.clear();
    });
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final endpoint in NetworkDiagnosticsService.endpoints.entries) {
        if (budget.elapsed > const Duration(seconds: 60)) break;
        final result = await service.sample(endpoint.key, endpoint.value);
        if (!mounted || !identical(service, _service)) return;
        setState(
          () => _samples.putIfAbsent(endpoint.key, () => []).add(result),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('networkDiagnostics'))),
      body: ContentFrame(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.t('networkExplanation')),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            for (final name in NetworkDiagnosticsService.endpoints.keys)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (context) {
                      final items = _samples[name] ?? [];
                      final times =
                          items
                              .where((e) => e.error == null)
                              .map((e) => e.totalMs!)
                              .toList()
                            ..sort();
                      final first = items.firstOrNull;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${s.t('networkSamples')}: ${first?.totalMs ?? '—'} / ${times.isEmpty ? '—' : times[times.length ~/ 2]} ms',
                          ),
                          for (var i = 0; i < items.length; i++)
                            Text(
                              '#${i + 1} · ${items[i].error == null ? '${items[i].headersMs == null ? '' : '${s.t('networkHeaders')}: ${items[i].headersMs} ms · '}${s.t('networkTotal')}: ${items[i].totalMs} ms' : s.t(items[i].error!)}',
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: Text(s.t('networkRun')),
            ),
            if (_busy)
              TextButton(
                onPressed: () {
                  _service?.close();
                  _service = null;
                  setState(() => _busy = false);
                },
                child: Text(s.t('cancel')),
              ),
          ],
        ),
      ),
    );
  }
}
