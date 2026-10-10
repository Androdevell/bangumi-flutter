import 'package:flutter/material.dart';

Future<String?> showCommentComposer(
  BuildContext context, {
  required String title,
  required String hint,
  int maxLength = 2000,
}) => showDialog<String>(
  context: context,
  builder:
      (_) => _CommentComposer(title: title, hint: hint, maxLength: maxLength),
);

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    required this.title,
    required this.hint,
    required this.maxLength,
  });
  final String title;
  final String hint;
  final int maxLength;
  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.add_comment_outlined),
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final text = _controller.text.trim();
          if (text.isNotEmpty) Navigator.pop(context, text);
        },
        child: const Text('发布'),
      ),
    ],
  );
}
