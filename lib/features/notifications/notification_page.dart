import 'package:flutter/material.dart';
import '../../widgets/open_website.dart';
import '../../app/app_links.dart';
import '../../core/localization/app_localizations.dart';
import '../../domain/models/notification.dart';
import 'notification_controller.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key, required this.controller});
  final NotificationController controller;
  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  Future<void> _open(ComposeNotice item) async {
    final scope = widget.controller.repository.scope;
    if (item.unread && !await widget.controller.markRead({item.id})) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('noticeReadFailed')),
        ),
      );
    }
    if (!mounted ||
        !widget.controller.loggedIn ||
        scope != widget.controller.repository.scope) {
      return;
    }
    try {
      if (!await AppLinkDispatcher.open(context, item.target)) {
        if (!mounted) return;
        await openWebsite(context, item.target);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).t('noticeOpenFailed')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.t('notifications')),
            actions: [
              IconButton(
                tooltip: s.t('refresh'),
                onPressed:
                    state.loading || state.marking
                        ? null
                        : widget.controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: s.t('noticeReadVisible'),
                onPressed:
                    state.marking ||
                            state.loading ||
                            !state.items.any((item) => item.unread)
                        ? null
                        : () => widget.controller.markRead(
                          state.items.map((item) => item.id).toSet(),
                        ),
                icon: const Icon(Icons.done_all),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(s.t('noticeAll')),
                          selected: !state.unreadOnly,
                          onSelected:
                              state.marking
                                  ? null
                                  : (_) => widget.controller.refresh(
                                    unreadOnly: false,
                                  ),
                        ),
                        ChoiceChip(
                          label: Text(
                            '${s.t('noticeUnread')} (${state.unreadCount})',
                          ),
                          selected: state.unreadOnly,
                          onSelected:
                              state.marking
                                  ? null
                                  : (_) => widget.controller.refresh(
                                    unreadOnly: true,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (state.loading || state.marking)
                    const LinearProgressIndicator(minHeight: 2),
                  if (state.error)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        s.t('noticeLoadFailed'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child:
                        !widget.controller.loggedIn
                            ? Center(child: Text(s.t('loginRequired')))
                            : RefreshIndicator(
                              onRefresh: widget.controller.refresh,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: state.items.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == state.items.length) {
                                    return Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        s.t(
                                          state.items.isEmpty &&
                                                  !state.loading &&
                                                  !state.error
                                              ? 'noticeEmpty'
                                              : 'noticeRecent',
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  final item = state.items[index];
                                  return Card(
                                    color:
                                        item.unread
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer
                                            : null,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(14),
                                      leading: Badge(
                                        isLabelVisible: item.unread,
                                        child: Icon(
                                          item.type == 14 || item.type == 15
                                              ? Icons.person_add_outlined
                                              : Icons.chat_bubble_outline,
                                        ),
                                      ),
                                      title: Text(
                                        '${item.nickname} · ${s.t(item.labelKey)}',
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (item.title.isNotEmpty)
                                            Text(
                                              item.title,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          if (item.createdAt != null)
                                            Text(
                                              MaterialLocalizations.of(
                                                context,
                                              ).formatShortDate(
                                                item.createdAt!.toLocal(),
                                              ),
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap:
                                          state.marking
                                              ? null
                                              : () => _open(item),
                                    ),
                                  );
                                },
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
