import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/bangumi_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import 'notification_controller.dart';
import 'notification_page.dart';

class NotificationHost extends StatefulWidget {
  const NotificationHost({
    super.key,
    required this.repository,
    required this.child,
  });
  final BangumiRepository repository;
  final Widget child;
  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost>
    with WidgetsBindingObserver {
  NotificationController? _controller;
  Timer? _timer;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _attach();
  }

  void _attach() {
    final repo = widget.repository;
    if (repo is NotificationFeature) {
      _controller = NotificationController(
        (repo as NotificationFeature).notifications,
      );
    }
    _schedule(const Duration(seconds: 5)); // 不与首页首屏争抢网络。
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_active || _controller == null) return;
    _timer = Timer(delay, () async {
      await _controller?.poll();
      if (mounted) _schedule(const Duration(minutes: 1));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _schedule(const Duration(seconds: 2));
  }

  @override
  void didUpdateWidget(NotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _controller?.dispose();
      _controller = null;
      _attach();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NotificationScope(controller: _controller, child: widget.child);
}

class _NotificationScope extends InheritedWidget {
  const _NotificationScope({required this.controller, required super.child});
  final NotificationController? controller;
  @override
  bool updateShouldNotify(_NotificationScope oldWidget) =>
      controller != oldWidget.controller;
}

class NotificationButton extends StatelessWidget {
  const NotificationButton({super.key});
  @override
  Widget build(BuildContext context) {
    final controller =
        context
            .dependOnInheritedWidgetOfExactType<_NotificationScope>()
            ?.controller;
    if (controller == null) return const SizedBox.shrink();
    final s = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => IconButton(
            tooltip: s.t('notifications'),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NotificationPage(controller: controller),
                  ),
                ),
            icon: Badge(
              isLabelVisible: controller.state.unreadCount > 0,
              label: Text(
                controller.state.unreadCount > 99
                    ? '99+'
                    : '${controller.state.unreadCount}',
              ),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
    );
  }
}
