import 'package:flutter/material.dart';

class PagedFooter extends StatelessWidget {
  const PagedFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    this.error,
  });
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Object? error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child:
        loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Column(
              children: [
                Text('$error'),
                TextButton(onPressed: onLoadMore, child: const Text('重试')),
              ],
            )
            : hasMore
            ? Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: const Text('加载更多'),
              ),
            )
            : const Center(child: Text('没有更多了')),
  );
}
