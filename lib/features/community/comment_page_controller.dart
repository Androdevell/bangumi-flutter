import 'package:flutter/foundation.dart';

@immutable
class ComposeCommentPageState<T> {
  const ComposeCommentPageState({
    this.data,
    this.loading = false,
    this.error,
    this.afterPublish = false,
  });
  final T? data;
  final bool loading, afterPublish;
  final Object? error;
}

/// 读取与发布结果独立；刷新失败保留旧列表，不把已确认的发布改判为失败。
class CommentPageController<T> extends ChangeNotifier {
  CommentPageController({required this.load, required this.session});
  final Future<T> Function() load;
  final Object Function() session;
  ComposeCommentPageState<T> state = ComposeCommentPageState<T>();
  bool _closed = false;
  int _generation = 0;
  Future<void> refresh({bool afterPublish = false, bool reset = false}) async {
    if (_closed || (state.loading && !reset && !afterPublish)) return;
    final generation = ++_generation;
    final scope = session();
    state = ComposeCommentPageState(
      data: reset ? null : state.data,
      loading: true,
      afterPublish: afterPublish,
    );
    notifyListeners();
    try {
      final result = await load();
      if (_closed || generation != _generation || scope != session()) return;
      state = ComposeCommentPageState(data: result);
    } on Object catch (error) {
      if (_closed || generation != _generation || scope != session()) return;
      state = ComposeCommentPageState(
        data: state.data,
        error: error,
        afterPublish: afterPublish,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
