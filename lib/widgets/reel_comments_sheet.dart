import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../services/course_reels_service.dart';
import '../theme/app_colors.dart';
import 'app_notify.dart';

/// Opens the comments for [lesson]. Keeps `lesson.commentCount` current, so
/// the caller only has to rebuild once the sheet closes.
Future<void> showReelCommentsSheet(
  BuildContext context, {
  required ReelLesson lesson,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReelCommentsSheet(lesson: lesson),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({required this.lesson});

  final ReelLesson lesson;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  static const _pageSize = 30;

  final List<ReelComment> _comments = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _total = 0;

  set _count(int value) {
    _total = value;
    widget.lesson.commentCount = value;
  }

  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _total = widget.lesson.commentCount;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final (items, total) = await CourseReelsService.fetchComments(
        widget.lesson.id,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(items);
        _count = total;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _comments.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final (items, total) = await CourseReelsService.fetchComments(
        widget.lesson.id,
        offset: _comments.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        final seen = _comments.map((c) => c.id).toSet();
        _comments.addAll(items.where((c) => !seen.contains(c.id)));
        _count = total;
      });
    } catch (_) {
      // Scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await CourseReelsService.postComment(
        widget.lesson.id,
        text,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _comments.insert(0, comment);
        _count = _total + 1;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        AppNotify.show(context, message: 'Couldn\'t post your comment');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ReelComment comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CourseReelsService.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _count = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (_) {
      if (mounted) {
        AppNotify.show(context, message: 'Couldn\'t delete the comment');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _total == 1 ? '1 comment' : '$_total comments',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Symbols.close_rounded, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(child: _list(c)),
            Divider(height: 1, color: c.border),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: c.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Add a comment…',
                          hintStyle: TextStyle(color: c.textTertiary),
                          counterText: '',
                          filled: true,
                          fillColor: c.surfaceAlt,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Symbols.send_rounded, color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(AppColors c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: const Text('Couldn\'t load comments — retry'),
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Text(
          'No comments yet. Start the conversation.',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _comments.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _comments.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final comment = _comments[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: c.surfaceAlt,
            backgroundImage: comment.authorImage != null
                ? NetworkImage(comment.authorImage!)
                : null,
            child: comment.authorImage == null
                ? Icon(Symbols.person_rounded, size: 20, color: c.textSecondary)
                : null,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  comment.authorName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _ago(comment.createdAt),
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              comment.text,
              style: TextStyle(
                fontSize: 14,
                color: c.textPrimary,
                height: 1.35,
              ),
            ),
          ),
          onLongPress: comment.isMine ? () => _delete(comment) : null,
          trailing: comment.isMine
              ? IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _delete(comment),
                  icon: Icon(
                    Symbols.delete_rounded,
                    size: 20,
                    color: c.textTertiary,
                  ),
                )
              : null,
        );
      },
    );
  }

  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at.toLocal());
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }
}
