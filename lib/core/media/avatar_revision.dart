/// 只使指定头像换用新缓存键，避免为更新头像清空全部作品图片。
abstract final class AvatarRevision {
  static final Map<String, int> _revisions = {};
  static Uri? _base(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'lain.bgm.tv') return null;
    final query = {...uri.queryParameters}..remove('_client_avatar');
    return uri.replace(queryParameters: query);
  }

  static void bump(String url) {
    final base = _base(url);
    if (base == null) return;
    if (_revisions.length >= 64) _revisions.remove(_revisions.keys.first);
    final now = DateTime.now().millisecondsSinceEpoch;
    _revisions[base.toString()] =
        now > (_revisions[base.toString()] ?? 0)
            ? now
            : _revisions[base.toString()]! + 1;
  }

  static String resolve(String url) {
    final base = _base(url);
    final revision = base == null ? null : _revisions[base.toString()];
    return revision == null
        ? url
        : base!
            .replace(
              queryParameters: {
                ...base.queryParameters,
                '_client_avatar': '$revision',
              },
            )
            .toString();
  }
}
