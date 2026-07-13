import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/skeleton.dart';

class MyReviewsScreen extends StatefulWidget {
  final bool isTutor;
  final int? tutorProfileId;

  const MyReviewsScreen({
    super.key,
    this.isTutor = false,
    this.tutorProfileId,
  });

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> list;
      if (widget.isTutor && widget.tutorProfileId != null) {
        final raw = await ApiService.getList('/tutors/${widget.tutorProfileId}/reviews/');
        list = raw.cast<Map<String, dynamic>>();
      } else {
        final data = await ApiService.get('/reviews/my/');
        list = (data['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      }
      if (!mounted) return;
      setState(() {
        _reviews = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEdit(Map<String, dynamic> review) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditReviewSheet(review: review),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        final i = _reviews.indexWhere((r) => r['id'] == updated['id']);
        if (i != -1) _reviews[i] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _Header(),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingList();
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    if (_reviews.isEmpty) return _EmptyState(isTutor: widget.isTutor);
    return RefreshIndicator(
      color: context.colors.textPrimary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        itemCount: _reviews.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ReviewCard(
          review: _reviews[i],
          isTutor: widget.isTutor,
          onEdit: widget.isTutor ? null : () => _openEdit(_reviews[i]),
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 24,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'My reviews',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

// ─── Review card ─────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final bool isTutor;
  final VoidCallback? onEdit;
  const _ReviewCard({required this.review, this.isTutor = false, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String? ?? '';
    final createdAt = _formatDate(review['created_at'] as String?);

    // For tutors: show the student who wrote the review.
    // For students: show the tutor being reviewed.
    final String participantName;
    final String? imageUrl;
    final String participantLabel;
    if (isTutor) {
      final student = review['student'] as Map<String, dynamic>?;
      participantLabel = 'Student';
      imageUrl = (student?['profile_image'] ?? student?['image'] ?? student?['avatar']) as String?;
      final displayName = (student?['display_name'] ?? student?['full_name'] ?? student?['name'])?.toString().trim() ?? '';
      if (displayName.isNotEmpty) {
        participantName = displayName;
      } else {
        final first = (student?['first_name'] ?? '').toString().trim();
        final last = (student?['last_name'] ?? '').toString().trim();
        participantName = '$first $last'.trim().isNotEmpty ? '$first $last'.trim() : 'Student';
      }
    } else {
      final tutor = review['tutor'] as Map<String, dynamic>?;
      participantLabel = 'Tutor';
      participantName = tutor?['display_name'] as String? ?? '';
      imageUrl = tutor?['image'] as String?;
    }

    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top accent bar with rating
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.brand,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                // Stars
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      i < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 20,
                      color: i < rating
                          ? colors.accentYellow
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                  )),
                ),
                const SizedBox(width: 8),
                Text(
                  '$rating / 5',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.accentYellow,
                  ),
                ),
                const Spacer(),
                Text(
                  createdAt,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Participant row
                Row(
                  children: [
                    CachedAvatar(imageUrl: imageUrl, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (participantName.isNotEmpty)
                            Text(
                              participantName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                          Text(
                            participantLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      comment,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─── Edit review sheet ───────────────────────────────────────────────────────

class _EditReviewSheet extends StatefulWidget {
  final Map<String, dynamic> review;
  const _EditReviewSheet({required this.review});

  @override
  State<_EditReviewSheet> createState() => _EditReviewSheetState();
}

class _EditReviewSheetState extends State<_EditReviewSheet> {
  late int _rating;
  late final TextEditingController _commentController;
  bool _saving = false;
  String? _error;

  static const _labels = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];

  @override
  void initState() {
    super.initState();
    _rating = (widget.review['rating'] as num?)?.toInt() ?? 5;
    _commentController = TextEditingController(
      text: widget.review['comment'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      setState(() => _error = 'Comment cannot be empty');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.review['id'];
      await ApiService.patch('/reviews/$id/edit/', {
        'rating': _rating,
        'comment': comment,
      });
      if (!mounted) return;
      Navigator.of(context).pop({
        ...widget.review,
        'rating': _rating,
        'comment': comment,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutor = widget.review['tutor'] as Map<String, dynamic>?;
    final tutorName = tutor?['display_name'] as String? ?? 'Tutor';
    final imageUrl = tutor?['image'] as String?;
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tutor info
            Row(
              children: [
                CachedAvatar(imageUrl: imageUrl, size: 44),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutorName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Edit your review',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Star picker
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: colors.brand.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < _rating;
                      return GestureDetector(
                        onTap: () => setState(() => _rating = i + 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: filled
                                ? colors.accentYellow
                                : colors.border,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _labels[(_rating - 1).clamp(0, 4)],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Comment field
            TextField(
              controller: _commentController,
              minLines: 3,
              maxLines: 5,
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: colors.textTertiary,
                ),
                filled: true,
                fillColor: colors.surfaceAlt,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.error,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Save button
            GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _saving
                      ? colors.brand.withValues(alpha: 0.5)
                      : colors.brand,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
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

// ─── Loading skeleton ────────────────────────────────────────────────────────

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF272942),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const Skeleton(height: 18, width: 120, borderRadius: 6),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Skeleton(height: 40, width: 40, circle: true),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton(height: 15, width: 130, borderRadius: 6),
                          SizedBox(height: 5),
                          Skeleton(height: 12, width: 50, borderRadius: 6),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Skeleton(height: 60, width: double.infinity, borderRadius: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isTutor;
  const _EmptyState({this.isTutor = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFEEEFF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_outline_rounded,
                size: 40,
                color: Color(0xFFF5C542),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isTutor
                  ? 'Reviews from your students will appear here.'
                  : 'Reviews you\'ve written for tutors will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFFAAAAAA),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
