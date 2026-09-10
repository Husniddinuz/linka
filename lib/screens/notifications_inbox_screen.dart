import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton.dart';
import 'notifications_screen.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  List<_InboxItem> _items = [];
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await NotificationService.fetchInbox(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = raw.map(_InboxItem.fromJson).toList()
          ..sort((a, b) {
            // Unread first, then newest-first within each group.
            if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
            return b.createdAt.compareTo(a.createdAt);
          });
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  Future<void> _markOne(_InboxItem item) async {
    if (item.isRead) return;
    setState(() => item.isRead = true);
    try {
      await NotificationService.markRead(item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => item.isRead = false);
    }
  }

  void _openDetail(_InboxItem item) {
    _markOne(item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(item: item),
    );
  }

  Future<void> _markAll() async {
    if (_markingAll || _items.every((i) => i.isRead)) return;
    setState(() {
      _markingAll = true;
      for (final i in _items) {
        i.isRead = true;
      }
    });
    try {
      await NotificationService.markAllRead();
    } catch (_) {
      // On failure, re-fetch to restore truth.
      await _load();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((i) => !i.isRead);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Symbols.chevron_left_rounded,
                      size: 30,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                    child: Icon(
                      Symbols.settings_rounded,
                      size: 24,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (hasUnread && !_loading)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: GestureDetector(
                    onTap: _markingAll ? null : _markAll,
                    child: Text(
                      'Mark all as read',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _markingAll
                            ? context.colors.textTertiary
                            : context.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                color: context.colors.textPrimary,
                onRefresh: _load,
                child: _loading
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: 6,
                        itemBuilder: (_, _) => const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Skeleton(height: 72, borderRadius: 14),
                        ),
                      )
                    : _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              _EmptyState(),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _InboxCard(
                              item: _items[i],
                              onTap: () => _openDetail(_items[i]),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Models ─────────────────────────────────────────────────────────────────

class _InboxItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  bool isRead;

  _InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
  });

  factory _InboxItem.fromJson(Map<String, dynamic> j) {
    final rawId = j['id'];
    final createdRaw = (j['created_at'] ?? j['timestamp'] ?? '').toString();
    final created = DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now();
    final read = j['is_read'] == true ||
        j['read'] == true ||
        (j['status']?.toString() == 'read');
    return _InboxItem(
      id: rawId?.toString() ?? '',
      title: (j['title'] ?? _titleForType(j['type']?.toString())).toString(),
      body: (j['body'] ?? j['message'] ?? '').toString(),
      type: (j['type'] ?? 'system').toString(),
      createdAt: created,
      isRead: read,
    );
  }
}

String _titleForType(String? type) {
  switch (type) {
    case 'lesson_reminder':
      return 'Lesson reminder';
    case 'recommended_tutors':
      return 'Recommended tutors';
    case 'new_features':
      return 'New features';
    case 'admin_test':
      return 'Message';
    default:
      return 'Notification';
  }
}

IconData _iconForType(String type) {
  switch (type) {
    case 'lesson_reminder':
      return Symbols.event_available_rounded;
    case 'recommended_tutors':
      return Symbols.person_search_rounded;
    case 'new_features':
      return Symbols.auto_awesome_rounded;
    default:
      return Symbols.notifications_rounded;
  }
}

String _timeAgo(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final d = when;
  return '${d.day}/${d.month}/${d.year % 100}';
}

// ─── Widgets ────────────────────────────────────────────────────────────────

class _InboxCard extends StatelessWidget {
  final _InboxItem item;
  final VoidCallback onTap;

  const _InboxCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: unread
              ? context.colors.accentYellow.withValues(alpha: 0.12)
              : context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread
                ? context.colors.accentYellow.withValues(alpha: 0.5)
                : context.colors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.brand,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconForType(item.type),
                color: context.colors.accentYellow,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(item.createdAt),
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: context.colors.textSecondary,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF2B2B),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationDetailSheet extends StatelessWidget {
  final _InboxItem item;

  const _NotificationDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.colors.brand,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(item.type),
              color: context.colors.accentYellow,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              item.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                item.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _timeAgo(item.createdAt),
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: context.colors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: context.colors.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Close',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/icons/notification_empty.svg',
          width: 40,
          height: 40,
        ),
        const SizedBox(height: 12),
        Text(
          'No notifications yet',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: context.colors.textTertiary,
          ),
        ),
      ],
    );
  }
}
