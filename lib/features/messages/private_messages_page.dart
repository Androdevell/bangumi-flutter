import 'package:flutter/material.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/repositories/private_message_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/localization/app_localizations.dart';
import '../../widgets/common.dart';
import '../../widgets/bangumi_rich_text.dart';

class PrivateMessageButton extends StatelessWidget {
  const PrivateMessageButton({
    super.key,
    required this.repository,
    this.recipient,
  });
  final BangumiRepository repository;
  final String? recipient;
  @override
  Widget build(BuildContext context) {
    if (repository is! PrivateMessageFeature) return const SizedBox.shrink();
    return IconButton(
      tooltip: AppLocalizations.of(context).t('privateMessages'),
      icon: const Icon(Icons.mail_outline),
      onPressed:
          !repository.isLoggedIn
              ? null
              : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) =>
                          recipient == null
                              ? PrivateMessagesPage(
                                repository:
                                    (repository as PrivateMessageFeature)
                                        .messages,
                              )
                              : PrivateMessageComposePage(
                                repository:
                                    (repository as PrivateMessageFeature)
                                        .messages,
                                recipient: recipient!,
                              ),
                ),
              ),
    );
  }
}

class PrivateMessagesPage extends StatefulWidget {
  const PrivateMessagesPage({super.key, required this.repository});
  final PrivateMessageRepository repository;
  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  String _folder = 'inbox';
  int _page = 1;
  late Future<ComposePrivatePage> _future = _load();
  Future<ComposePrivatePage> _load() =>
      widget.repository.load(folder: _folder, page: _page);
  void _reset() {
    if (mounted) {
      setState(() {
        _page = 1;
        _future = _load();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.sessionChanges.addListener(_reset);
  }

  @override
  void dispose() {
    widget.repository.sessionChanges.removeListener(_reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('privateMessages')),
        actions: [
          IconButton(
            tooltip: s.t('newMessage'),
            icon: const Icon(Icons.edit_square),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => PrivateMessageComposePage(
                          repository: widget.repository,
                        ),
                  ),
                ),
          ),
        ],
      ),
      body: ContentFrame(
        maxWidth: 880,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final folder in ['inbox', 'outbox'])
                    ChoiceChip(
                      label: Text(s.t(folder)),
                      selected: _folder == folder,
                      onSelected:
                          (_) => setState(() {
                            _folder = folder;
                            _page = 1;
                            _future = _load();
                          }),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<ComposePrivatePage>(
                key: ValueKey('${widget.repository.scope}:$_folder:$_page'),
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return NetworkErrorView(
                      error: snapshot.error!,
                      onRetry: _reset,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!;
                  return ListView(
                    children: [
                      if (data.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text(s.t('messageEmpty')),
                        ),
                      for (final item in data.items)
                        ListTile(
                          leading: Icon(
                            item.unread
                                ? Icons.mark_email_unread_outlined
                                : Icons.mail_outline,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              item.sender,
                              item.time,
                              item.content,
                            ].where((v) => v.isNotEmpty).join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder:
                                      (_) => PrivateMessageThreadPage(
                                        repository: widget.repository,
                                        path: item.path,
                                        title: item.title,
                                      ),
                                ),
                              ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed:
                                _page > 1
                                    ? () => setState(() {
                                      _page--;
                                      _future = _load();
                                    })
                                    : null,
                            child: Text(s.t('previous')),
                          ),
                          Text('$_page'),
                          TextButton(
                            onPressed:
                                data.hasMore
                                    ? () => setState(() {
                                      _page++;
                                      _future = _load();
                                    })
                                    : null,
                            child: Text(s.t('next')),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivateMessageThreadPage extends StatefulWidget {
  const PrivateMessageThreadPage({
    super.key,
    required this.repository,
    required this.path,
    required this.title,
  });
  final PrivateMessageRepository repository;
  final String path, title;
  @override
  State<PrivateMessageThreadPage> createState() =>
      _PrivateMessageThreadPageState();
}

class _PrivateMessageThreadPageState extends State<PrivateMessageThreadPage> {
  late Future<List<ComposePrivateMessage>> _future = widget.repository.thread(
    widget.path,
  );
  void _reset() {
    if (mounted) {
      setState(() => _future = widget.repository.thread(widget.path));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.sessionChanges.addListener(_reset);
  }

  @override
  void dispose() {
    widget.repository.sessionChanges.removeListener(_reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.reply),
            label: Text(s.t('reply')),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => PrivateMessageComposePage(
                        repository: widget.repository,
                        threadPath: widget.path,
                      ),
                ),
              );
              _reset();
            },
          ),
        ),
      ),
      body: ContentFrame(
        maxWidth: 880,
        child: FutureBuilder<List<ComposePrivateMessage>>(
          key: ValueKey(widget.repository.scope),
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return NetworkErrorView(error: snapshot.error!, onRetry: _reset);
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, i) {
                final item = snapshot.data![i];
                return Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.sender,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          item.time,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        BangumiRichText(item.content),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class PrivateMessageComposePage extends StatefulWidget {
  const PrivateMessageComposePage({
    super.key,
    required this.repository,
    this.recipient = '',
    this.threadPath,
  });
  final PrivateMessageRepository repository;
  final String recipient;
  final String? threadPath;
  @override
  State<PrivateMessageComposePage> createState() =>
      _PrivateMessageComposePageState();
}

class _PrivateMessageComposePageState extends State<PrivateMessageComposePage> {
  final _recipient = TextEditingController(),
      _title = TextEditingController(),
      _body = TextEditingController();
  ComposePrivateForm? _form;
  Object? _error;
  bool _busy = false, _unknown = false, _changed = false, _allowPop = false;
  late final _scope = widget.repository.scope;
  void _sessionChanged() {
    if (widget.repository.scope != _scope && mounted) {
      setState(() {
        _changed = true;
        _recipient.clear();
        _title.clear();
        _body.clear();
        _form = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.sessionChanges.addListener(_sessionChanged);
    _load();
  }

  Future<void> _load() async {
    try {
      final form = await widget.repository.form(
        recipient: widget.recipient,
        threadPath: widget.threadPath,
      );
      if (!mounted || widget.repository.scope != _scope) return;
      setState(() {
        _form = form;
        _recipient.text =
            widget.recipient.isEmpty
                ? form.fields['msg_receivers'] ?? ''
                : widget.recipient;
        _title.text = form.fields['msg_title'] ?? '';
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    if (_busy || _unknown || _changed || _form == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.send(
        _form!,
        recipient: _recipient.text,
        title: _title.text,
        content: _body.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).t('messageSent'))),
      );
      setState(() => _allowPop = true);
      Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _unknown = e is ApiException && e.outcomeUnknown;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.repository.sessionChanges.removeListener(_sessionChanged);
    _recipient.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: _allowPop || _body.text.isEmpty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        final discard = await showDialog<bool>(
          context: context,
          builder:
              (c) => AlertDialog(
                title: Text(s.t('discardDraft')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(s.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(s.t('confirm')),
                  ),
                ],
              ),
        );
        if (discard == true && mounted && context.mounted) {
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.t('newMessage'))),
        body: ContentFrame(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_changed) Text(s.t('commentSessionChanged')),
              if (_form == null && _error == null && !_changed)
                const LinearProgressIndicator(),
              TextField(
                controller: _recipient,
                enabled: !_busy && !_changed,
                decoration: InputDecoration(labelText: s.t('receiver')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                enabled: !_busy && !_changed,
                maxLength: 200,
                decoration: InputDecoration(labelText: s.t('messageTitle')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_busy && !_changed,
                minLines: 6,
                maxLines: 16,
                maxLength: 10000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: s.t('messageBody'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    s.t(
                      _unknown
                          ? 'messageUnknown'
                          : _error is ApiException
                          ? (_error as ApiException).message
                          : 'operationFailed',
                    ),
                  ),
                ),
              if (_form == null && _error != null && !_changed)
                TextButton(onPressed: _load, child: Text(s.t('retry'))),
              FilledButton.icon(
                onPressed:
                    _busy ||
                            _unknown ||
                            _changed ||
                            _form == null ||
                            _body.text.trim().isEmpty
                        ? null
                        : _send,
                icon:
                    _busy
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.send),
                label: Text(s.t('sendMessage')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
