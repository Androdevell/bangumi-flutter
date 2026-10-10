import 'package:flutter/material.dart';

class SectionFailureNotice extends StatelessWidget {
  const SectionFailureNotice({
    super.key,
    required this.errors,
    required this.onRetry,
  });
  final Map<String, String> errors;
  final VoidCallback onRetry;
  static const _labels = {
    'episodes': '章节',
    'comments': '评论',
    'characters': '角色',
    'staffs': '制作人员',
    'relations': '关联',
    'indexes': '目录',
    'reviews': '日志',
    'topics': '话题',
    'timeline': '时间线',
    'collections': '收藏',
    'persons': '人物',
    'blogs': '日志',
    'friends': '好友',
    'works': '作品',
    'collectors': '收藏用户',
  };
  @override
  Widget build(BuildContext context) =>
      errors.isEmpty
          ? const SizedBox.shrink()
          : Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '部分内容加载失败：${errors.keys.map((key) => _labels[key] ?? key).join('、')}',
                      maxLines: 2,
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
            ),
          );
}
