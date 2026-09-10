import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../theme/app_colors.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _hasError = false;
  final Set<int> _unblocking = {};

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final raw = await ChatService.fetchBlockedUsers();
      if (mounted) setState(() { _users = raw; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _unblock(int userId) async {
    if (_unblocking.contains(userId)) return;
    setState(() => _unblocking.add(userId));
    try {
      await ChatService.unblockUser(userId: userId);
      if (!mounted) return;
      setState(() {
        _unblocking.remove(userId);
        _users.removeWhere((u) => (u['user_id'] as num).toInt() == userId);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _unblocking.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return 'Blocked ${dt.day} ${_months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 48,
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back_ios_new_rounded, size: 18),
          color: context.colors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Blocked users',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: context.colors.border),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.accentBlue),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load blocked users.',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _load,
              child: Text(
                'Try again',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  color: context.colors.accentBlue,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Text(
          "You haven't blocked anyone.",
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 15,
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) {
        final u = _users[i];
        final userId = (u['user_id'] as num).toInt();
        final name = u['name']?.toString() ?? 'Unknown';
        final blockedAt = _formatDate(u['blocked_at'] as String?);
        final isUnblocking = _unblocking.contains(userId);

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: context.colors.accentBlue.withValues(alpha: 0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontWeight: FontWeight.w600,
                color: context.colors.accentBlue,
              ),
            ),
          ),
          title: Text(
            name,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimary,
            ),
          ),
          subtitle: blockedAt.isNotEmpty
              ? Text(
                  blockedAt,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    color: context.colors.textTertiary,
                  ),
                )
              : null,
          trailing: isUnblocking
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.accentBlue,
                  ),
                )
              : TextButton(
                  onPressed: () => _unblock(userId),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.accentBlue,
                    textStyle: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Unblock'),
                ),
        );
      },
    );
  }
}
