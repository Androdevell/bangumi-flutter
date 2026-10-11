import 'package:flutter/material.dart';
import 'common.dart';

/// 仅挂载已访问标签页；相邻预构建不会提前触发业务读取。
class LazyTabView extends StatefulWidget {
  const LazyTabView({super.key, required this.builders});
  final List<Widget Function()> builders;
  @override
  State<LazyTabView> createState() => _LazyTabViewState();
}

class _LazyTabViewState extends State<LazyTabView> {
  TabController? _controller;
  final Set<int> _visited = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.of(context);
    if (_controller != next) {
      _controller?.removeListener(_changed);
      _controller = next..addListener(_changed);
      _visited.add(next.index);
    }
  }

  void _changed() {
    if (mounted) setState(() => _visited.add(_controller!.index));
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TabBarView(
    children: [
      for (var index = 0; index < widget.builders.length; index++)
        TickerMode(
          enabled: _controller!.index == index,
          child:
              _visited.contains(index)
                  ? _RetainedTab(child: widget.builders[index]())
                  : const SizedBox.shrink(),
        ),
    ],
  );
}

class _RetainedTab extends StatefulWidget {
  const _RetainedTab({required this.child});
  final Widget child;
  @override
  State<_RetainedTab> createState() => _RetainedTabState();
}

class _RetainedTabState extends State<_RetainedTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class SectionLoader<T> extends StatefulWidget {
  const SectionLoader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(T) builder;
  @override
  State<SectionLoader<T>> createState() => _SectionLoaderState<T>();
}

class _SectionLoaderState<T> extends State<SectionLoader<T>> {
  late Future<T> _future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return NetworkErrorView(
          error: snapshot.error!,
          onRetry: () => setState(() => _future = widget.load()),
        );
      }
      if (!snapshot.hasData) return const LoadingView();
      return widget.builder(snapshot.data as T);
    },
  );
}
