import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'tutor_profile_screen.dart';

class SavedTutorsScreen extends StatefulWidget {
  const SavedTutorsScreen({super.key});

  @override
  State<SavedTutorsScreen> createState() => _SavedTutorsScreenState();
}

class _SavedTutorsScreenState extends State<SavedTutorsScreen> {
  List<Map<String, dynamic>> _tutors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService.get('/student/saved-tutors/');
      final list = response['data'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _tutors = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _removeBookmark(int tutorId) async {
    try {
      await ApiService.delete('/student/saved-tutors/$tutorId/');
      setState(() => _tutors.removeWhere((t) => t['id'] == tutorId));
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 30,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Saved tutors',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 30),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: context.colors.textPrimary),
                    )
                  : _tutors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'assets/images/icons/bookmark_outline_16.svg',
                                width: 40,
                                height: 40,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No saved tutors yet',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: context.colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: () {
                              final cardWidth =
                                  (MediaQuery.of(context).size.width - 52) / 2;
                              final imageHeight = cardWidth * 2 / 3;
                              return cardWidth / (imageHeight + 100);
                            }(),
                          ),
                          itemCount: _tutors.length,
                          itemBuilder: (_, i) {
                            final t = _tutors[i];
                            final id = t['id'] as int? ?? 0;
                            final name = t['tutor_name'] as String? ?? '';
                            final image = t['profile_image'] as String?;
                            int exp = 0;
                            final rawExp = t['experience'];
                            if (rawExp is int) {
                              exp = rawExp;
                            } else if (rawExp is String) {
                              final match = RegExp(r'(\d+)').firstMatch(rawExp);
                              if (match != null) exp = int.parse(match.group(1)!);
                            }
                            final score = (t['ielts_score'] as num?)?.toDouble() ?? 0;

                            return GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TutorProfileScreen(tutorId: id),
                                ),
                              ),
                              child: _SavedTutorCard(
                                name: name,
                                image: image,
                                experience: exp,
                                score: score,
                                onRemove: () => _removeBookmark(id),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedTutorCard extends StatelessWidget {
  final String name;
  final String? image;
  final int experience;
  final double score;
  final VoidCallback onRemove;

  const _SavedTutorCard({
    required this.name,
    this.image,
    required this.experience,
    required this.score,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: image != null
                  ? Image.network(
                      image!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: context.colors.border,
                        child: Icon(Icons.person, size: 40, color: context.colors.textTertiary),
                      ),
                    )
                  : Container(
                      color: context.colors.border,
                      child: Icon(Icons.person, size: 40, color: context.colors.textTertiary),
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Experience: +$experience yrs',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'IELTS ${score % 1 == 0 ? score.toInt() : score}',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.colors.error,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onRemove,
                      child: SvgPicture.asset(
                        'assets/images/icons/bookmarked.svg',
                        width: 18,
                        height: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
