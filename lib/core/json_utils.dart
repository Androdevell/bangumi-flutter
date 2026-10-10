/// 时间缺失、非法或超出范围时返回 null，不伪造当前时间。
DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final number = value is num ? value : num.tryParse(text);
  if (number != null) {
    if (!number.isFinite || number <= 0) return null;
    final millis = number < 100000000000 ? number * 1000 : number;
    if (millis > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      millis.toInt(),
      isUtc: true,
    ).toLocal();
  }
  return DateTime.tryParse(text)?.toLocal();
}

String dateText(DateTime? value) =>
    value == null
        ? '—'
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String relativeTime(DateTime? value, {DateTime? now}) {
  if (value == null) return '—';
  final difference = (now ?? DateTime.now()).difference(value);
  if (difference.isNegative) return dateText(value);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
  if (difference.inHours < 24) return '${difference.inHours} 小时前';
  if (difference.inDays < 30) return '${difference.inDays} 天前';
  return dateText(value);
}
