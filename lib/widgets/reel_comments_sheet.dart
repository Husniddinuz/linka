import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Replies under one top-level comment, fetched the first time it's opened.
class _Thread {
  final List<ReelComment> replies = [];
  bool expanded = false;
  bool loading = false;

  /// Replies on the server; more can be fetched while this exceeds the list.
  int total = 0;
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  static const _pageSize = 30;

  final List<ReelComment> _comments = [];
  final Map<int, _Thread> _threads = {};
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  /// Top-level comments on the server, for paging.
  int _topTotal = 0;

  /// Comments and replies together, as the header and the feed show them.
  int get _total => widget.lesson.commentCount;
  set _total(int value) => widget.lesson.commentCount = value < 0 ? 0 : value;

  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _failed = false;

  /// The comment the composer is answering, and the root its reply goes under.
  ReelComment? _replyTo;
  ReelComment? _replyRoot;

  /// The comment the composer is rewriting.
  ReelComment? _editing;

  @override
  void initState() {
    super.initState();
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
    _inputFocus.dispose();
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
        _threads.clear();
        _topTotal = total;
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
    if (_loading || _loadingMore || _comments.length >= _topTotal) return;
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
        _topTotal = total;
      });
    } catch (_) {
      // Scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  _Thread _thread(ReelComment root) => _threads.putIfAbsent(root.id, () {
    return _Thread()..total = root.replyCount;
  });

  /// Opens [root]'s replies, or fetches the next page when already open.
  Future<void> _loadReplies(ReelComment root) async {
    final t = _thread(root);
    if (t.loading) return;
    setState(() {
      t.expanded = true;
      t.loading = true;
    });
    try {
      final (items, total) = await CourseReelsService.fetchReplies(
        root.id,
        offset: t.replies.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        final seen = t.replies.map((r) => r.id).toSet();
        t.replies.addAll(items.where((r) => !seen.contains(r.id)));
        t.total = total;
        root.replyCount = total;
      });
    } catch (_) {
      if (mounted) {
        AppNotify.show(context, message: 'Couldn\'t load replies');
      }
    } finally {
      if (mounted) setState(() => t.loading = false);
    }
  }

  void _startReply(ReelComment comment, ReelComment root) {
    final name = _name(comment);
    setState(() {
      _editing = null;
      _replyTo = comment;
      _replyRoot = root;
    });
    // Answering a reply names its author, since it lands in the same thread.
    _input.text = comment.id == root.id ? '' : '@$name ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _inputFocus.requestFocus();
  }

  void _startEdit(ReelComment comment) {
    setState(() {
      _replyTo = null;
      _replyRoot = null;
      _editing = comment;
    });
    _input.text = comment.text;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _inputFocus.requestFocus();
  }

  void _cancelComposerMode() {
    setState(() {
      _replyTo = null;
      _replyRoot = null;
      _editing = null;
    });
    _input.clear();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final editing = _editing;
    final root = _replyRoot;
    try {
      if (editing != null) {
        final saved = await CourseReelsService.editComment(editing.id, text);
        if (!mounted) return;
        setState(() {
          editing
            ..text = saved.text
            ..isEdited = saved.isEdited;
          _editing = null;
        });
        _input.clear();
        return;
      }
      final comment = await CourseReelsService.postComment(
        widget.lesson.id,
        text,
        parentId: root?.id,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _total = _total + 1;
        _replyTo = null;
        _replyRoot = null;
        if (root == null) {
          _comments.insert(0, comment);
          _topTotal++;
        } else {
          final t = _thread(root);
          root.replyCount++;
          t
            ..expanded = true
            ..total += 1
            ..replies.add(comment);
        }
      });
      if (root == null && _scroll.hasClients) _scroll.jumpTo(0);
      // A thread that was never opened only holds the new reply; fill in the
      // ones before it.
      if (root != null && _thread(root).replies.length < root.replyCount) {
        final t = _thread(root);
        t.replies.remove(comment);
        await _loadReplies(root);
        if (mounted && !t.replies.any((r) => r.id == comment.id)) {
          setState(() => t.replies.add(comment));
        }
      }
    } catch (_) {
      if (mounted) {
        AppNotify.show(
          context,
          message: editing != null
              ? 'Couldn\'t save your changes'
              : 'Couldn\'t post your comment',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(ReelComment comment) async {
    final liked = !comment.isLiked;
    setState(() {
      comment.isLiked = liked;
      comment.likeCount = (comment.likeCount + (liked ? 1 : -1)).clamp(
        0,
        1 << 30,
      );
    });
    try {
      final (on, count) = await CourseReelsService.setCommentLiked(
        comment.id,
        liked,
      );
      if (!mounted) return;
      setState(() {
        comment.isLiked = on;
        comment.likeCount = count;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        comment.isLiked = !liked;
        comment.likeCount = (comment.likeCount + (liked ? -1 : 1)).clamp(
          0,
          1 << 30,
        );
      });
    }
  }

  Future<void> _delete(ReelComment comment, ReelComment root) async {
    final isRoot = comment.id == root.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: isRoot && comment.replyCount > 0
            ? const Text('Its replies will be deleted too.')
            : null,
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
        if (_editing?.id == comment.id ||
            _replyTo?.id == comment.id ||
            (isRoot && _replyRoot?.id == comment.id)) {
          _editing = null;
          _replyTo = null;
          _replyRoot = null;
          _input.clear();
        }
        if (isRoot) {
          _comments.removeWhere((c) => c.id == comment.id);
          _threads.remove(comment.id);
          _topTotal = (_topTotal - 1).clamp(0, 1 << 30);
          _total = _total - 1 - comment.replyCount;
        } else {
          final t = _thread(root);
          t.replies.removeWhere((r) => r.id == comment.id);
          t.total = (t.total - 1).clamp(0, 1 << 30);
          root.replyCount = (root.replyCount - 1).clamp(0, 1 << 30);
          _total = _total - 1;
        }
      });
    } catch (_) {
      if (mounted) {
        AppNotify.show(context, message: 'Couldn\'t delete the comment');
      }
    }
  }

  Future<void> _openMenu(ReelComment comment, ReelComment root) async {
    final c = context.colors;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Symbols.reply_rounded, color: c.textPrimary),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              ListTile(
                leading: Icon(
                  Symbols.content_copy_rounded,
                  color: c.textPrimary,
                ),
                title: const Text('Copy text'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              if (comment.isMine) ...[
                ListTile(
                  leading: Icon(Symbols.edit_rounded, color: c.textPrimary),
                  title: const Text('Edit'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                ListTile(
                  leading: Icon(Symbols.delete_rounded, color: c.error),
                  title: Text('Delete', style: TextStyle(color: c.error)),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'reply':
        _startReply(comment, root);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: comment.text));
        if (mounted) AppNotify.show(context, message: 'Copied');
      case 'edit':
        _startEdit(comment);
      case 'delete':
        await _delete(comment, root);
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
            if (_replyTo != null || _editing != null) _composerBanner(c),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _inputFocus,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: c.textPrimary),
                        decoration: InputDecoration(
                          hintText: _replyTo != null
                              ? 'Reply to ${_name(_replyTo!)}…'
                              : 'Add a comment…',
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
                          : Icon(
                              _editing != null
                                  ? Symbols.check_rounded
                                  : Symbols.send_rounded,
                              color: c.textPrimary,
                            ),
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

  Widget _composerBanner(AppColors c) {
    final label = _editing != null
        ? 'Editing your comment'
        : 'Replying to ${_name(_replyTo!)}';
    return Container(
      color: c.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      child: Row(
        children: [
          Icon(
            _editing != null ? Symbols.edit_rounded : Symbols.reply_rounded,
            size: 16,
            color: c.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            onPressed: _cancelComposerMode,
            icon: Icon(Symbols.close_rounded, size: 18, color: c.textSecondary),
          ),
        ],
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
        final root = _comments[i];
        final t = _threads[root.id];
        final shown = t != null && t.expanded
            ? t.replies
            : const <ReelComment>[];
        final hidden = root.replyCount - shown.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tile(c, root, root),
            for (final reply in shown) _tile(c, reply, root),
            if (root.replyCount > 0) _repliesToggle(c, root, t, hidden),
          ],
        );
      },
    );
  }

  Widget _repliesToggle(AppColors c, ReelComment root, _Thread? t, int hidden) {
    final loading = t?.loading ?? false;
    final open = t?.expanded ?? false;
    final String label;
    if (!open) {
      label = root.replyCount == 1
          ? 'View 1 reply'
          : 'View ${root.replyCount} replies';
    } else if (hidden > 0) {
      label = hidden == 1 ? 'View 1 more reply' : 'View $hidden more replies';
    } else {
      label = 'Hide replies';
    }
    return Padding(
      padding: const EdgeInsets.only(left: 66, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: c.textSecondary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: loading
              ? null
              : () {
                  if (open && hidden <= 0) {
                    setState(() => t!.expanded = false);
                  } else if (!open &&
                      t != null &&
                      t.replies.length >= root.replyCount) {
                    setState(() => t.expanded = true);
                  } else {
                    _loadReplies(root);
                  }
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 24, height: 1, color: c.border),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(AppColors c, ReelComment comment, ReelComment root) {
    final isReply = comment.id != root.id;
    final avatar = isReply ? 12.0 : 18.0;
    final meta = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: c.textTertiary,
    );
    return InkWell(
      onLongPress: () => _openMenu(comment, root),
      onDoubleTap: comment.isLiked ? null : () => _toggleLike(comment),
      child: Padding(
        padding: EdgeInsets.fromLTRB(isReply ? 66 : 16, 8, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: avatar,
              backgroundColor: c.surfaceAlt,
              backgroundImage: comment.authorImage != null
                  ? NetworkImage(comment.authorImage!)
                  : null,
              child: comment.authorImage == null
                  ? Icon(
                      Symbols.person_rounded,
                      size: avatar * 1.1,
                      color: c.textSecondary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _name(comment),
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
                      if (comment.isEdited) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· edited',
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  Row(
                    children: [
                      _metaButton(
                        'Reply',
                        meta,
                        () => _startReply(comment, root),
                      ),
                      if (comment.isMine) ...[
                        _metaButton('Edit', meta, () => _startEdit(comment)),
                        _metaButton(
                          'Delete',
                          meta,
                          () => _delete(comment, root),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  IconButton(
                    tooltip: comment.isLiked ? 'Unlike' : 'Like',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _toggleLike(comment),
                    icon: Icon(
                      Symbols.favorite_rounded,
                      fill: comment.isLiked ? 1 : 0,
                      size: 18,
                      color: comment.isLiked
                          ? Colors.redAccent
                          : c.textTertiary,
                    ),
                  ),
                  if (comment.likeCount > 0)
                    Text(
                      '${comment.likeCount}',
                      style: TextStyle(fontSize: 11, color: c.textTertiary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _metaButton(String label, TextStyle style, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 14, 6),
        child: Text(label, style: style),
      ),
    );
  }

  static String _name(ReelComment comment) =>
      comment.authorName.isEmpty ? 'Linka student' : comment.authorName;

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
