import 'package:flutter/foundation.dart';

/// 值相等辅助函数。
///
/// 模型里大量存在 `Set<String>` / `Map<String, int>` /
/// `Map<String, Set<String>>` 字段。`Object.==` 与 `foundation` 的
/// `mapEquals` 对集合字段只做一层比较，嵌套 `Set` 会被当成引用比较而
/// 静默失效，因此这里统一提供深比较与配套哈希。
///
/// 约定：任何使用这些函数的模型，其 `hashCode` 必须用对应的 `*Hash`
/// 生成，保证「`==` 相等则 `hashCode` 相等」。

/// 比较两个 `Set<String>`。
bool stringSetEquals(Set<String> a, Set<String> b) => setEquals(a, b);

/// 比较两个 `Map<String, int>`。
bool intMapEquals(Map<String, int> a, Map<String, int> b) => mapEquals(a, b);

/// 比较两个 `Map<String, Set<String>>`。
///
/// `mapEquals` 会拿 `Set` 的引用去比较，因此必须逐层展开。
bool mapOfSetEquals(Map<String, Set<String>> a, Map<String, Set<String>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (!setEquals(entry.value, other)) return false;
  }
  return true;
}

/// `Set<String>` 的顺序无关哈希。
int stringSetHash(Set<String> value) => Object.hashAllUnordered(value);

/// `Map<String, int>` 的顺序无关哈希。
int intMapHash(Map<String, int> value) => Object.hashAllUnordered(
  value.entries.map((entry) => Object.hash(entry.key, entry.value)),
);

/// `Map<String, Set<String>>` 的顺序无关哈希。
int mapOfSetHash(Map<String, Set<String>> value) => Object.hashAllUnordered(
  value.entries.map(
    (entry) => Object.hash(entry.key, Object.hashAllUnordered(entry.value)),
  ),
);
