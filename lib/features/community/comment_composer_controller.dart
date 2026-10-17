import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';

enum CommentSubmitStatus {
  editing,
  submitting,
  failed,
  unknown,
  confirmed,
  stale,
}

@immutable
class ComposeCommentComposerState {
  const ComposeCommentComposerState({
    this.value = TextEditingValue.empty,
    this.preview = false,
    this.status = CommentSubmitStatus.editing,
    this.error,
  });
  final TextEditingValue value;
  final bool preview;
  final CommentSubmitStatus status;
  final Object? error;
}

sealed class CommentComposerIntent {}

class EditComment extends CommentComposerIntent {
  EditComment(this.value);
  final TextEditingValue value;
}

class PreviewComment extends CommentComposerIntent {}

class SubmitComment extends CommentComposerIntent {}

/// 内存草稿、选区与提交状态由同一控制器管理；未知结果保持锁定直到用户核实。
class CommentComposerController extends ChangeNotifier {
  CommentComposerController({
    required this.maxLength,
    required this.submit,
    required this.isCurrent,
    TextEditingValue initial = TextEditingValue.empty,
  }) : state = ComposeCommentComposerState(value: initial);
  final int maxLength;
  final Future<void> Function(String) submit;
  final bool Function() isCurrent;
  ComposeCommentComposerState state;
  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  bool _closed = false;
  bool get busy => state.status == CommentSubmitStatus.submitting;
  bool get canSubmit =>
      !busy &&
      state.status != CommentSubmitStatus.confirmed &&
      state.status != CommentSubmitStatus.unknown &&
      state.status != CommentSubmitStatus.stale &&
      state.value.text.trim().isNotEmpty &&
      state.value.text.characters.length <= maxLength &&
      state.value.composing.isCollapsed;
  void acknowledgeNotSent() {
    if (state.status == CommentSubmitStatus.unknown && !busy) {
      _set(status: CommentSubmitStatus.editing);
    }
  }

  void dispatch(CommentComposerIntent intent) {
    if (_closed || busy) return;
    if (intent is EditComment) {
      if (intent.value == state.value) return;
      if (intent.value.text != state.value.text) {
        _undo.add(state.value);
        if (_undo.length > 80) _undo.removeAt(0);
        _redo.clear();
      }
      _set(value: intent.value);
    } else if (intent is PreviewComment) {
      _set(preview: !state.preview);
    } else if (intent is SubmitComment && canSubmit) {
      _send();
    }
  }

  void wrap(String tag) => insert('[$tag]', '[/${tag.split('=').first}]');
  void insert(String prefix, [String suffix = '']) {
    if (busy || !state.value.composing.isCollapsed) return;
    final value = state.value;
    final rawSelection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final boundaries = <int>[0];
    for (final character in value.text.characters) {
      boundaries.add(boundaries.last + character.length);
    }
    final start = boundaries.lastWhere(
      (offset) => offset <= rawSelection.start.clamp(0, value.text.length),
    );
    final end =
        rawSelection.isCollapsed
            ? start
            : boundaries.firstWhere(
              (offset) =>
                  offset >= rawSelection.end.clamp(0, value.text.length),
            );
    final selection = TextSelection(baseOffset: start, extentOffset: end);
    final selected = value.text.substring(start, end);
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selected$suffix',
    );
    dispatch(
      EditComment(
        TextEditingValue(
          text: text,
          selection: TextSelection(
            baseOffset: selection.start + prefix.length,
            extentOffset: selection.start + prefix.length + selected.length,
          ),
        ),
      ),
    );
  }

  void undo({bool redo = false}) {
    if (busy || !state.value.composing.isCollapsed) return;
    final source = redo ? _redo : _undo;
    if (source.isEmpty) return;
    (redo ? _undo : _redo).add(state.value);
    _set(value: source.removeLast());
  }

  void _set({
    TextEditingValue? value,
    bool? preview,
    CommentSubmitStatus? status,
    Object? error,
  }) {
    if (_closed) return;
    state = ComposeCommentComposerState(
      value: value ?? state.value,
      preview: preview ?? state.preview,
      status: status ?? state.status,
      error: error ?? state.error,
    );
    notifyListeners();
  }

  Future<void> _send() async {
    if (!isCurrent()) {
      _set(status: CommentSubmitStatus.stale);
      return;
    }
    _set(status: CommentSubmitStatus.submitting);
    try {
      await submit(state.value.text.trim());
      _set(
        status:
            isCurrent()
                ? CommentSubmitStatus.confirmed
                : CommentSubmitStatus.stale,
      );
    } on Object catch (error) {
      _set(
        status:
            !isCurrent()
                ? CommentSubmitStatus.stale
                : error is ApiException && !error.outcomeUnknown
                ? CommentSubmitStatus.failed
                : CommentSubmitStatus.unknown,
        error: error,
      );
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
