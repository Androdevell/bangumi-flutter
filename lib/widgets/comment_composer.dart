import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/localization/app_localizations.dart';
import '../core/text/bbcode_document.dart';
import '../core/network/api_client.dart';
import '../features/community/comment_composer_controller.dart';
import '../domain/use_cases/comment_submit_use_case.dart';
import '../data/bangumi_repository.dart';
import 'bangumi_rich_text.dart';

class _UrlInputDialog extends StatefulWidget {
  const _UrlInputDialog({required this.image});
  final bool image;
  @override
  State<_UrlInputDialog> createState() => _UrlInputDialogState();
}

class _UrlInputDialogState extends State<_UrlInputDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.t(widget.image ? 'insertImage' : 'insertLink')),
      content: TextField(
        controller: _input,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://…'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _input.text),
          child: Text(strings.t('insert')),
        ),
      ],
    );
  }
}

/// 草稿生命周期属于当前页面，不跨账号复制，不持久化私人正文。
class CommentEditorSession {
  CommentComposerController? _controller;
  CommentSubmitUseCase? _useCase;
  bool get needsVerification =>
      _controller?.state.status == CommentSubmitStatus.unknown;
  Future<String?> open(
    BuildContext context,
    BangumiRepository repository,
    ComposeCommentTarget target,
  ) async {
    if (_controller == null ||
        (_controller!.state.value.text.isEmpty && !_useCase!.isCurrent)) {
      _controller?.dispose();
      final useCase = _useCase = CommentSubmitUseCase(repository, target);
      _controller = CommentComposerController(
        maxLength: target.maxLength,
        submit: useCase.call,
        isCurrent: () => useCase.isCurrent,
      );
    }
    final strings = AppLocalizations.of(context);
    final result = await showCommentComposer(
      context,
      title: strings.t('postComment'),
      hint: strings.t('commentHint'),
      target: target.title,
      username: _useCase!.scope.username,
      controller: _controller,
    );
    if (result != null || (_controller?.state.value.text.isEmpty ?? true)) {
      _controller?.dispose();
      _controller = null;
      _useCase = null;
    }
    return result;
  }

  void dispose() => _controller?.dispose();
}

Future<String?> showCommentComposer(
  BuildContext context, {
  required String title,
  required String hint,
  int maxLength = 2000,
  String target = '',
  String username = '',
  CommentComposerController? controller,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder:
      (_) => _CommentComposer(
        title: title,
        hint: hint,
        maxLength: maxLength,
        target: target,
        username: username,
        controller: controller,
      ),
);

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    required this.title,
    required this.hint,
    required this.maxLength,
    required this.target,
    required this.username,
    this.controller,
  });
  final String title, hint, target, username;
  final int maxLength;
  final CommentComposerController? controller;
  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  late final _model =
      widget.controller ??
      CommentComposerController(
        maxLength: widget.maxLength,
        submit: (_) async {},
        isCurrent: () => true,
      );
  late final _text = TextEditingController.fromValue(_model.state.value);
  final _focus = FocusNode();
  bool _allowPop = false,
      _closing = false,
      _syncing = false,
      _confirmed = false;
  AppLocalizations get strings => AppLocalizations.of(context);
  String get _failureKey {
    final error = _model.state.error;
    if (error is ApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'loginComment';
      }
      if (error.message == 'commentInvalid') return 'commentInvalid';
    }
    return 'commentFailed';
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
    _model.addListener(_changed);
  }

  void _edited() {
    if (!_syncing) _model.dispatch(EditComment(_text.value));
  }

  void _changed() {
    if (!mounted) return;
    if (_text.value != _model.state.value) {
      _syncing = true;
      _text.value = _model.state.value;
      _syncing = false;
    }
    if (_model.state.status == CommentSubmitStatus.confirmed && !_confirmed) {
      _confirmed = true;
      _finish(_text.text.trim());
    } else {
      setState(() {});
    }
  }

  void _finish(String? result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  Future<void> _close() async {
    if (_closing || _model.busy) return;
    _closing = true;
    if (widget.controller != null && _text.text.isNotEmpty) {
      final decision = await showDialog<int>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(strings.t('closeDraft')),
              content: Text(strings.t('draftMemoryHint')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 0),
                  child: Text(strings.t('keepEditing')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 1),
                  child: Text(strings.t('discardDraft')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 2),
                  child: Text(strings.t('keepDraft')),
                ),
              ],
            ),
      );
      if (!mounted) return;
      if (decision == 0 || decision == null) {
        _closing = false;
        return;
      }
      if (decision == 1) _model.dispatch(EditComment(TextEditingValue.empty));
    }
    if (mounted) _finish(null);
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    if (widget.controller == null) _model.dispose();
    super.dispose();
  }

  void _wrap(String tag) {
    _model.wrap(tag);
    _focus.requestFocus();
  }

  Future<void> _insertUrl(bool image) async {
    final uriText = await showDialog<String>(
      context: context,
      builder: (_) => _UrlInputDialog(image: image),
    );
    if (!mounted || uriText == null) return;
    final uri = BangumiBbCode.safeUrl(uriText);
    if (uri == null ||
        uri.toString().contains('[') ||
        uri.toString().contains(']')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('unsafeUrl'))));
      return;
    }
    if (image) {
      _model.insert('[img]$uri[/img]');
    } else if (_text.selection.isValid && !_text.selection.isCollapsed) {
      _model.wrap('url=$uri');
    } else {
      _model.insert('[url]$uri[/url]');
    }
    _focus.requestFocus();
  }

  Future<void> _emojis() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: 280,
              child: GridView.count(
                crossAxisCount: 6,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final value in [
                    'bgm38',
                    'bgm46',
                    'bgm63',
                    'bgm64',
                    'bgm67',
                    'bgm69',
                    'bgm72',
                    'bgm74',
                    'bgm88',
                    'bgm106',
                    'musume_15',
                    'blake_03',
                  ])
                    IconButton(
                      tooltip: '($value)',
                      onPressed: () => Navigator.pop(context, '($value)'),
                      icon: FittedBox(
                        child: BangumiRichText('($value)', selectable: false),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
    if (!mounted || code == null) return;
    _model.insert(code);
    _focus.requestFocus();
  }

  Future<void> _more(String value) async {
    if (value == 'clear' || value == 'verified') {
      final verified = value == 'verified';
      final allow = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                strings.t(verified ? 'verifyBeforeResend' : 'clearDraft'),
              ),
              content: verified ? Text(strings.t('unknownSubmit')) : null,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    strings.t(verified ? 'verifiedNotSent' : 'clear'),
                  ),
                ),
              ],
            ),
      );
      if (allow == true) {
        if (verified) {
          _model.acknowledgeNotSent();
        } else {
          _model.dispatch(EditComment(TextEditingValue.empty));
        }
      }
    } else {
      _wrap(value);
    }
  }

  Widget _tool(IconData icon, String key, VoidCallback callback) => IconButton(
    tooltip: strings.t(key),
    onPressed:
        _model.busy ||
                _model.state.preview ||
                !_model.state.value.composing.isCollapsed
            ? null
            : callback,
    icon: Icon(icon, size: 21),
  );
  Widget _toolbar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _tool(Icons.format_bold, 'formatBold', () => _wrap('b')),
        _tool(Icons.format_italic, 'formatItalic', () => _wrap('i')),
        _tool(Icons.format_underlined, 'formatUnderline', () => _wrap('u')),
        _tool(Icons.format_strikethrough, 'formatStrike', () => _wrap('s')),
        _tool(Icons.link, 'insertLink', () => _insertUrl(false)),
        _tool(Icons.image_outlined, 'insertImage', () => _insertUrl(true)),
        _tool(Icons.format_quote, 'quote', () => _wrap('quote')),
        _tool(Icons.visibility_off_outlined, 'spoiler', () => _wrap('mask')),
        _tool(Icons.emoji_emotions_outlined, 'emoticons', _emojis),
        _tool(Icons.undo, 'undo', () => _model.undo()),
        _tool(Icons.redo, 'redo', () => _model.undo(redo: true)),
        PopupMenuButton<String>(
          tooltip: strings.t('more'),
          enabled: !_model.busy && _model.state.value.composing.isCollapsed,
          onSelected: _more,
          itemBuilder:
              (_) => [
                for (final entry
                    in {
                      'size=18': 'largeText',
                      'color=#ff4081': 'pinkText',
                      'clear': 'clear',
                    }.entries)
                  PopupMenuItem(
                    value: entry.key,
                    child: Text(strings.t(entry.value)),
                  ),
                if (_model.state.status == CommentSubmitStatus.unknown)
                  PopupMenuItem(
                    value: 'verified',
                    child: Text(strings.t('verifiedNotSent')),
                  ),
              ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final state = _model.state;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.edit_note_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (widget.username.isNotEmpty)
                      Text(
                        '@${widget.username}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _model.busy ? null : _close,
                child: Text(strings.t('cancel')),
              ),
            ],
          ),
        ),
        if (widget.target.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.target,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        _toolbar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child:
                state.preview
                    ? DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: BangumiRichText(state.value.text),
                      ),
                    )
                    : TextField(
                      key: const ValueKey('comment-input'),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      readOnly: _model.busy,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      maxLength: _model.maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        counterText: '',
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
          ),
        ),
        if (state.status == CommentSubmitStatus.failed ||
            state.status == CommentSubmitStatus.unknown ||
            state.status == CommentSubmitStatus.stale)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 112),
              child: SingleChildScrollView(
                child: Text(
                  strings.t(
                    state.status == CommentSubmitStatus.unknown
                        ? 'unknownSubmit'
                        : state.status == CommentSubmitStatus.stale
                        ? 'commentSessionChanged'
                        : _failureKey,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        _model.busy
                            ? null
                            : () => _model.dispatch(PreviewComment()),
                    icon: Icon(
                      state.preview
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(strings.t(state.preview ? 'edit' : 'preview')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${state.value.text.characters.length} / ${_model.maxLength}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      state.value.text.characters.length > _model.maxLength
                          ? Theme.of(context).colorScheme.error
                          : null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.t('spoilerHint'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    _model.canSubmit
                        ? () => _model.dispatch(SubmitComment())
                        : null,
                icon:
                    _model.busy
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.send_rounded, size: 18),
                label: Text(strings.t('publish')),
              ),
            ],
          ),
        ),
      ],
    );
    final shortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_model.canSubmit) _model.dispatch(SubmitComment());
        },
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: LayoutBuilder(
        builder:
            (context, constraints) => SingleChildScrollView(
              child: SizedBox(
                height: math.max(
                  constraints.maxHeight,
                  420 +
                      MediaQuery.textScalerOf(context).scale(100) +
                      (state.status == CommentSubmitStatus.unknown ||
                              state.status == CommentSubmitStatus.stale ||
                              state.status == CommentSubmitStatus.failed
                          ? 140
                          : 0),
                ),
                child: SafeArea(child: content),
              ),
            ),
      ),
    );
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child:
          compact
              ? Dialog.fullscreen(child: shortcuts)
              : Dialog(
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerLowest,
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 820,
                  height: math.max(
                    260,
                    math.min(
                      680,
                      MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          48,
                    ),
                  ),
                  child: shortcuts,
                ),
              ),
    );
  }
}
