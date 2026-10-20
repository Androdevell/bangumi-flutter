import 'dart:async';

class ReadCancelledException implements Exception {
  const ReadCancelledException();
  @override
  String toString() => 'Read cancelled';
}

/// 查询拥有自己的读取生命周期；共享网络请求仅在所有消费者离开时取消。
class ReadTaskScope {
  static final _key = Object();
  static ReadTaskScope? get current => Zone.current[_key] as ReadTaskScope?;
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const ReadCancelledException();
  }

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_key: this});
  Future<T> wait<T>(Future<T> action) {
    check();
    return Future.any([
      action,
      whenCancelled.then<T>((_) => throw const ReadCancelledException()),
    ]);
  }
}
