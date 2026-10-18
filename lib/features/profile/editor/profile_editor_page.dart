import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_image_cache.dart';
import '../../../domain/models/account_settings.dart';
import '../../../domain/repositories/account_settings_repository.dart';
import '../../../widgets/avatar_crop_dialog.dart';
import '../../../widgets/bangumi_rich_text.dart';
import '../../../widgets/common.dart';
import 'profile_editor_controller.dart';

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({super.key, required this.repository});
  final AccountSettingsRepository repository;
  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final _model = ProfileEditorController(widget.repository);
  final _fields = {
    for (final key in ComposeAccountSettings.editableFields)
      key: TextEditingController(),
  };
  final _form = GlobalKey<FormState>();
  ComposeAccountSettings? _original;
  Uint8List? _avatar;
  bool _restricted = false,
      _preview = false,
      _allowPop = false,
      _picking = false;
  bool get _dirty =>
      _avatar != null ||
      (_original != null &&
          (_fields.entries.any(
                (e) => e.value.text != _original!.value(e.key),
              ) ||
              (_original!.restrictedField != null &&
                  _restricted !=
                      _original!.fields.containsKey(
                        _original!.restrictedField,
                      ))));
  @override
  void initState() {
    super.initState();
    for (final field in _fields.values) {
      field.addListener(_textChanged);
    }
    _model.addListener(_sync);
    _model.load();
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    final original = _model.state.original;
    if (original != null && _original == null) _fill(original);
    if (mounted) setState(() {});
  }

  void _fill(ComposeAccountSettings original) {
    _original = original;
    for (final entry in _fields.entries) {
      entry.value.text = original.value(entry.key);
    }
    _restricted =
        original.restrictedField != null &&
        original.fields.containsKey(original.restrictedField);
    _avatar = null;
  }

  Future<void> _reload() async {
    if (_dirty && !await _discard()) return;
    await _model.load();
    if (mounted &&
        _model.state.error == null &&
        _model.state.original != null) {
      setState(() => _fill(_model.state.original!));
    }
  }

  Future<bool> _discard() async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              content: Text(AppLocalizations.of(context).t('discardEdits')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context).t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(AppLocalizations.of(context).t('confirm')),
                ),
              ],
            ),
      ) ==
      true;
  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('5 MB');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final avatar = await cropAvatar(context, bytes);
      if (avatar != null && mounted && !_model.state.stale) {
        setState(() => _avatar = avatar);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).t('avatarHint'))),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _original == null) return;
    final edits = {
      for (final entry in _fields.entries)
        if (entry.value.text != _original!.value(entry.key))
          entry.key: entry.value.text,
    };
    final restricted = _original!.restrictedField;
    if (restricted != null &&
        _restricted != _original!.fields.containsKey(restricted)) {
      edits[restricted] =
          _restricted ? (_original!.checkboxValues[restricted] ?? 'on') : '';
    }
    if (edits.isEmpty && _avatar == null) return;
    final saved = await _model.save(edits, avatar: _avatar);
    if (!mounted) return;
    if (saved) {
      setState(() => _fill(_model.state.original!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).t('profileSaved'))),
      );
    }
  }

  @override
  void dispose() {
    _model.removeListener(_sync);
    _model.dispose();
    for (final field in _fields.values) {
      field.removeListener(_textChanged);
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = _model.state;
    final locked = state.loading || state.saving || state.stale || _picking;
    return PopScope(
      canPop: _allowPop || (!_dirty && !state.saving && !_picking),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || state.saving || _picking) return;
        if (!_dirty || await _discard()) {
          if (!context.mounted) return;
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(strings.t('editProfile'))),
        body: ContentFrame(
          maxWidth: 780,
          child:
              _original == null
                  ? state.error != null
                      ? NetworkErrorView(error: state.error!, onRetry: _reload)
                      : const LoadingView()
                  : Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (state.loading || state.saving)
                          const LinearProgressIndicator(minHeight: 2),
                        if (state.stale)
                          Text(
                            strings.t('commentSessionChanged'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (state.error != null)
                          Text(
                            state.error is ApiException
                                ? strings.t(
                                  (state.error as ApiException).message,
                                )
                                : strings.t('saveFailed'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (state.unknown)
                          TextButton(
                            onPressed: _reload,
                            child: Text(strings.t('reloadProfile')),
                          ),
                        Text(
                          '@${_original!.session.username} · ${strings.t('readOnlyUsername')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final size in [100.0, 54.0, 32.0])
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox.square(
                                  dimension: size,
                                  child:
                                      _avatar != null
                                          ? Image.memory(
                                            _avatar!,
                                            fit: BoxFit.cover,
                                          )
                                          : _original!.avatarUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                            imageUrl: _original!.avatarUrl,
                                            cacheManager: AppImageCache.manager,
                                            fit: BoxFit.cover,
                                          )
                                          : const Icon(Icons.person_outline),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: locked ? null : _pick,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text(strings.t('chooseAvatar')),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            strings.t('avatarHint'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (final entry
                            in {
                              'nickname': 'nickname',
                              'sign_input': 'signature',
                              'newsite': 'homepage',
                              'newbio': 'bio',
                            }.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextFormField(
                              controller: _fields[entry.key],
                              enabled: !locked,
                              minLines: entry.key == 'newbio' ? 5 : 1,
                              maxLines: entry.key == 'newbio' ? 12 : 1,
                              decoration: InputDecoration(
                                labelText: strings.t(entry.value),
                                prefixText:
                                    entry.key == 'newsite' &&
                                            _original!.sitePrefix.isNotEmpty
                                        ? _original!.sitePrefix
                                        : null,
                                helperText:
                                    entry.key == 'newbio'
                                        ? strings.t('profileIntroHint')
                                        : null,
                                helperMaxLines: 3,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = value ?? '';
                                if (text == _original!.value(entry.key)) {
                                  return null;
                                }
                                final limit = _original!.maxLengths[entry.key];
                                if ((entry.key == 'nickname' &&
                                        text.trim().isEmpty) ||
                                    (limit != null && text.length > limit)) {
                                  return strings.t('fieldInvalid');
                                }
                                if (entry.key == 'newsite' && text.isNotEmpty) {
                                  if (_original!.sitePrefix.isNotEmpty &&
                                      text.contains('://')) {
                                    return strings.t('fieldInvalid');
                                  }
                                  final uri = Uri.tryParse(
                                    '${_original!.sitePrefix}$text',
                                  );
                                  if (uri == null ||
                                      !{'http', 'https'}.contains(uri.scheme) ||
                                      uri.host.isEmpty ||
                                      uri.userInfo.isNotEmpty) {
                                    return strings.t('fieldInvalid');
                                  }
                                }
                                if (entry.key == 'newbio' &&
                                    RegExp(
                                      r'\[img(?:=|\])',
                                      caseSensitive: false,
                                    ).hasMatch(text)) {
                                  return strings.t('profileIntroHint');
                                }
                                return null;
                              },
                            ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.t('preview')),
                          value: _preview,
                          onChanged:
                              (value) => setState(() => _preview = value),
                        ),
                        if (_preview)
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _fields['newbio']!,
                            builder:
                                (_, value, __) => SurfaceBlock(
                                  child: BangumiRichText(value.text),
                                ),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value:
                              _original!.timezones.containsKey(
                                    _fields['timeoffsetnew']!.text,
                                  )
                                  ? _fields['timeoffsetnew']!.text
                                  : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: strings.t('timezone'),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final zone in _original!.timezones.entries)
                              DropdownMenuItem(
                                value: zone.key,
                                child: Text(
                                  zone.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged:
                              locked
                                  ? null
                                  : (value) {
                                    if (value != null) {
                                      setState(
                                        () =>
                                            _fields['timeoffsetnew']!.text =
                                                value,
                                      );
                                    }
                                  },
                        ),
                        if (_original!.restrictedField != null)
                          SwitchListTile(
                            title: Text(strings.t('restrictedContent')),
                            value: _restricted,
                            onChanged:
                                locked
                                    ? null
                                    : (value) =>
                                        setState(() => _restricted = value),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: locked || state.unknown ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(strings.t('saveProfile')),
                        ),
                        TextButton(
                          onPressed: locked ? null : _reload,
                          child: Text(strings.t('reloadProfile')),
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}
