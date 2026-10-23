import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/update/app_update_service.dart';
import '../../core/update/update_download_service.dart';
import '../../widgets/common.dart';
import '../../widgets/release_markdown.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final _service = AppUpdateService();
  final _download = UpdateDownloadService();
  late Future<AppUpdateResult> _result = _service.check();
  @override
  void dispose() {
    _download.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _open() async {
    var success = false;
    try {
      success =
          Platform.isAndroid
              ? await _download.installAndroid()
              : await launchUrl(Uri.directory(_download.file!.parent.path));
    } on Object {
      /* 由界面给出可操作的失败信息。 */
    }
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('downloadOpenFailed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('checkUpdate'))),
      body: ContentFrame(
        maxWidth: 780,
        child: FutureBuilder(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return NetworkErrorView(
                error: snapshot.error!,
                onRetry: () => setState(() => _result = _service.check()),
              );
            }
            final result = snapshot.data;
            if (result == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final asset = result.assetFor(android: Platform.isAndroid);
            return ListenableBuilder(
              listenable: _download,
              builder:
                  (context, _) => ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        result.updateAvailable
                            ? s.t('newVersion')
                            : s.t('latestVersion'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${s.t('currentVersion')}: ${result.currentVersion}\n${s.t('newestVersion')}: ${result.latestVersion}',
                      ),
                      if (result.publishedAt != null)
                        Text(
                          result.publishedAt!
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                        ),
                      const SizedBox(height: 18),
                      SurfaceBlock(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s.t('updateNotes'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            ReleaseMarkdown(
                              result.notes.isEmpty
                                  ? s.t('updateNoNotes')
                                  : result.notes,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (asset != null) ...[
                        Text(
                          '${asset.name} · ${(asset.size / 1048576).toStringAsFixed(1)} MB',
                        ),
                        const SizedBox(height: 12),
                        if (_download.busy) ...[
                          LinearProgressIndicator(
                            value:
                                _download.total > 0
                                    ? _download.received / _download.total
                                    : null,
                          ),
                          Text(
                            '${(_download.received / 1048576).toStringAsFixed(1)} / ${(_download.total / 1048576).toStringAsFixed(1)} MB · ${(_download.bytesPerSecond / 1024).toStringAsFixed(0)} KB/s',
                          ),
                          OutlinedButton(
                            onPressed: _download.cancel,
                            child: Text(s.t('downloadCancel')),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed:
                                asset.digest == null
                                    ? null
                                    : () =>
                                        unawaited(_download.download(asset)),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              s.t(
                                result.updateAvailable
                                    ? 'download'
                                    : 'downloadAgain',
                              ),
                            ),
                          ),
                        if (asset.digest == null) Text(s.t('downloadNoDigest')),
                        if (_download.error != null)
                          Text(
                            s.t(_download.error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_download.file != null) ...[
                          Text(s.t('downloadReady')),
                          Text(
                            s.t(
                              _download.verified
                                  ? 'downloadVerified'
                                  : 'downloadNoDigest',
                            ),
                          ),
                          SelectableText(_download.file!.path),
                          if (!Platform.isAndroid)
                            Text(s.t('downloadWindowsHint')),
                          FilledButton(
                            onPressed: _open,
                            child: Text(
                              s.t(
                                Platform.isAndroid
                                    ? 'downloadInstall'
                                    : 'downloadFolder',
                              ),
                            ),
                          ),
                        ],
                      ] else
                        Text(s.t('downloadMissing')),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            if (!await _service.openRelease(result)) {
                              throw StateError('open');
                            }
                          } on Object {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(s.t('downloadOpenFailed')),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: Text(s.t('openRelease')),
                      ),
                    ],
                  ),
            );
          },
        ),
      ),
    );
  }
}
