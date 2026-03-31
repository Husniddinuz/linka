import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import 'tutor_profile_screen.dart';

// ─── Data model ─────────────────────────────────────────────────────────────────

class _TutorCard {
  final int id;
  final String name;
  final String? image;
  final int experience;
  final double score;
  final bool isBookmarked;
  const _TutorCard({
    required this.id,
    required this.name,
    this.image,
    required this.experience,
    required this.score,
    this.isBookmarked = false,
  });

  factory _TutorCard.fromJson(Map<String, dynamic> json) {
    final firstName = json['first_name'] as String? ?? '';
    final lastName = json['last_name'] as String? ?? '';
    // experience can be int or descriptive string — extract leading number
    int exp = 0;
    final rawExp = json['experience'];
    if (rawExp is int) {
      exp = rawExp;
    } else if (rawExp is String) {
      final match = RegExp(r'(\d+)').firstMatch(rawExp);
      if (match != null) exp = int.parse(match.group(1)!);
    }
    return _TutorCard(
      id: json['id'] as int? ?? 0,
      name: '$firstName $lastName'.trim(),
      image: json['profile_image'] as String?,
      experience: exp,
      score: (json['ielts_score'] as num?)?.toDouble() ?? 0,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
    );
  }
}

class _TutorFilters {
  final String? gender;
  final String? ieltsScore;
  final int? experienceMin;
  final int? experienceMax;
  final String? search;

  const _TutorFilters({
    this.gender,
    this.ieltsScore,
    this.experienceMin,
    this.experienceMax,
    this.search,
  });

  String toQueryString() {
    final params = <String, String>{};
    if (gender != null) params['gender'] = gender!;
    if (ieltsScore != null) params['ielts_score'] = ieltsScore!;
    if (experienceMin != null) params['experience_min'] = '$experienceMin';
    if (experienceMax != null) params['experience_max'] = '$experienceMax';
    if (search != null && search!.isNotEmpty) params['search'] = search!;
    if (params.isEmpty) return '';
    return '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }
}

// ─── Screen ─────────────────────────────────────────────────────────────────────

class TutorsScreen extends StatefulWidget {
  const TutorsScreen({super.key});

  @override
  State<TutorsScreen> createState() => _TutorsScreenState();
}

class _TutorsScreenState extends State<TutorsScreen> {
  bool _showSearch = false;
  final _searchController = TextEditingController();
  final _recentSearches = [
    'Sardor Qodirov',
    'Nigora Mamatova',
    'Bekzod Tursunov',
  ];

  List<_TutorCard> _tutors = [];
  bool _loading = true;
  String? _error;
  _TutorFilters _filters = const _TutorFilters();

  @override
  void initState() {
    super.initState();
    _loadTutors();
  }

  Future<void> _loadTutors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getList(
        '/tutors/${_filters.toQueryString()}',
      );
      if (!mounted) return;
      setState(() {
        _tutors = list
            .map((e) => _TutorCard.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      dev.log('TUTORS ERROR: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _showFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_TutorFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(filters: _filters),
    );
    if (result != null) {
      _filters = result;
      _loadTutors();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSearch) {
      return _SearchView(
        controller: _searchController,
        recentSearches: _recentSearches,
        onClose: () => setState(() {
          _showSearch = false;
          _searchController.clear();
        }),
        onRemove: (i) => setState(() => _recentSearches.removeAt(i)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Search bar + filter + bookmark
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Search field
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showSearch = true),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              'assets/images/icons/search_20.svg',
                              width: 24,
                              height: 24,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Search for a tutor',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFAAAAAA),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Filter button
                  GestureDetector(
                    onTap: () => _showFilterSheet(context),
                    child: SvgPicture.asset(
                      'assets/images/icons/sliders_outline_20.svg',
                      width: 28,
                      height: 28,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Bookmark button
                  SvgPicture.asset(
                    'assets/images/icons/bookmark_outline_16.svg',
                    width: 26,
                    height: 26,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tutors grid
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF272942),
                      ),
                    )
                  : _tutors.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error != null
                                ? 'Failed to load tutors'
                                : 'No tutors found',
                            style: const TextStyle(
                              color: Color(0xFF2B2B2B),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFAAAAAA),
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: _loadTutors,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF272942),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontFamily: 'SF Pro',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                TutorProfileScreen(tutorId: _tutors[i].id),
                          ),
                        ),
                        child: _TutorGridCard(tutor: _tutors[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tutor grid card ────────────────────────────────────────────────────────────

class _TutorGridCard extends StatelessWidget {
  final _TutorCard tutor;
  const _TutorGridCard({required this.tutor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tutor image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: tutor.image != null
                  ? Image.network(
                      tutor.image!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFE0E0E0),
                        child: const Icon(
                          Icons.person,
                          size: 40,
                          color: Color(0xFFAAAAAA),
                        ),
                      ),
                    )
                  : Container(
                      color: const Color(0xFFE0E0E0),
                      child: const Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
            ),
          ),

          // Info section
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  tutor.name,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B2B2B),
                    height: 1.0,
                  ),
                ),

                const SizedBox(height: 6),

                // Experience
                Text(
                  'Experience: +${tutor.experience} yrs',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6C6C6C),
                    height: 1.0,
                  ),
                ),

                const SizedBox(height: 10),

                // IELTS score + bookmark
                Row(
                  children: [
                    // IELTS badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'IELTS ${tutor.score % 1 == 0 ? tutor.score.toInt() : tutor.score}',
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFC62828),
                          height: 1.0,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Bookmark icon
                    SvgPicture.asset(
                      tutor.isBookmarked
                          ? 'assets/images/icons/bookmarked.svg'
                          : 'assets/images/icons/bookmark_on_card.svg',
                      width: 18,
                      height: 20,
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

// ─── Search view ────────────────────────────────────────────────────────────────

class _SearchView extends StatelessWidget {
  final TextEditingController controller;
  final List<String> recentSearches;
  final VoidCallback onClose;
  final void Function(int) onRemove;

  const _SearchView({
    required this.controller,
    required this.recentSearches,
    required this.onClose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // Search bar with close
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/images/icons/search_20.svg',
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        color: Color(0xFF2B2B2B),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search for a tutor',
                        hintStyle: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15,
                          color: Color(0xFFAAAAAA),
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF2B2B2B),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFFEEEEEE)),

            // Recent searches header
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                'Вы недавно искали',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            ),

            // Recent search items
            ...List.generate(
              recentSearches.length,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 20,
                      color: Color(0xFFAAAAAA),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        recentSearches[i],
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15,
                          color: Color(0xFF2B2B2B),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onRemove(i),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFFAAAAAA),
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
}

// ─── Filter sheet ───────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final _TutorFilters filters;
  const _FilterSheet({required this.filters});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _timeSlots = [
    '9:00 - 12:00',
    '12:00 - 15:00',
    '15:00 - 18:00',
    '18:00 - 21:00',
    '21:00 - 0:00',
    '00:00 - 03:00',
  ];
  static const _ieltsScores = ['6.5', '7.0', '7.5', '8.0', '8.5', '9.0'];
  static const _genders = ['Male', 'Female'];
  static const _experiences = ['1-3 yrs', '3-5 yrs', '5-8 yrs', '8+ years'];

  static const _experienceRanges = {
    '1-3 yrs': (1, 3),
    '3-5 yrs': (3, 5),
    '5-8 yrs': (5, 8),
    '8+ years': (8, null),
  };

  final Set<String> _selectedTimes = {};
  final Set<String> _selectedDays = {};
  String? _selectedScore;
  String? _selectedGender;
  String? _selectedExperience;

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.filters.gender;
    _selectedScore = widget.filters.ieltsScore;
    // Restore experience label from min/max
    if (widget.filters.experienceMin != null) {
      for (final entry in _experienceRanges.entries) {
        if (entry.value.$1 == widget.filters.experienceMin) {
          _selectedExperience = entry.key;
          break;
        }
      }
    }
  }

  _TutorFilters _buildFilters() {
    int? expMin, expMax;
    if (_selectedExperience != null) {
      final range = _experienceRanges[_selectedExperience];
      if (range != null) {
        expMin = range.$1;
        expMax = range.$2;
      }
    }
    return _TutorFilters(
      gender: _selectedGender,
      ieltsScore: _selectedScore,
      experienceMin: expMin,
      experienceMax: expMax,
    );
  }

  void _openCalendarDialog(BuildContext context) {
    DateTime calendarMonth = DateTime(2026, 3);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              color: Colors.transparent,
              child: _FilterCalendar(
                focusedMonth: calendarMonth,
                selectedDays: _selectedDays,
                onPrevMonth: () => setDialogState(() {
                  calendarMonth = DateTime(
                    calendarMonth.year,
                    calendarMonth.month - 1,
                  );
                }),
                onNextMonth: () => setDialogState(() {
                  calendarMonth = DateTime(
                    calendarMonth.year,
                    calendarMonth.month + 1,
                  );
                }),
                onDayTap: (dayLabel) {
                  setDialogState(() {
                    if (_selectedDays.contains(dayLabel)) {
                      _selectedDays.remove(dayLabel);
                    } else {
                      _selectedDays.add(dayLabel);
                    }
                  });
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          controller: scrollController,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                const Spacer(),
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B2B2B),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close,
                    size: 24,
                    color: Color(0xFF2B2B2B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Availability
            _sectionTitleSvg(
              'assets/images/icons/calendar_outline_20.svg',
              'Availability',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._selectedDays.map(
                  (d) => _chipButton(
                    d,
                    true,
                    () => setState(() => _selectedDays.remove(d)),
                  ),
                ),
                _chipButton('+ Add a day', false, () {
                  _openCalendarDialog(context);
                }),
              ],
            ),

            const SizedBox(height: 28),
            const Divider(color: Color(0xFFEEEEEE)),
            const SizedBox(height: 20),

            // Time
            _sectionTitleSvg(
              'assets/images/icons/recent_outline_grey.svg',
              'Time',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _timeSlots
                  .map(
                    (t) => _chipButton(
                      t,
                      _selectedTimes.contains(t),
                      () => setState(() {
                        _selectedTimes.contains(t)
                            ? _selectedTimes.remove(t)
                            : _selectedTimes.add(t);
                      }),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 28),
            const Divider(color: Color(0xFFEEEEEE)),
            const SizedBox(height: 20),

            // IELTS score
            _sectionTitleSvg(
              'assets/images/icons/live_outline_20.svg',
              'IELTS score',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ieltsScores
                  .map(
                    (s) => _chipButton(
                      s,
                      _selectedScore == s,
                      () => setState(
                        () => _selectedScore = _selectedScore == s ? null : s,
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 28),
            const Divider(color: Color(0xFFEEEEEE)),
            const SizedBox(height: 20),

            // Gender
            _sectionTitleSvg(
              'assets/images/icons/accessibility_outline_20 (1).svg',
              'Gender',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _genders
                  .map(
                    (g) => _chipButton(
                      g,
                      _selectedGender == g,
                      () => setState(
                        () => _selectedGender = _selectedGender == g ? null : g,
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 28),
            const Divider(color: Color(0xFFEEEEEE)),
            const SizedBox(height: 20),

            // Experience
            _sectionTitleSvg(
              'assets/images/icons/work_outline_20.svg',
              'Experience',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _experiences
                  .map(
                    (e) => _chipButton(
                      e,
                      _selectedExperience == e,
                      () => setState(
                        () => _selectedExperience = _selectedExperience == e
                            ? null
                            : e,
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 32),

            // Apply button
            Builder(
              builder: (_) {
                final hasSelection =
                    _selectedTimes.isNotEmpty ||
                    _selectedScore != null ||
                    _selectedGender != null ||
                    _selectedExperience != null ||
                    _selectedDays.isNotEmpty;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, _buildFilters()),
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: hasSelection
                          ? const Color(0xFF272942)
                          : const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Apply',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: hasSelection
                              ? Colors.white
                              : const Color(0xFF6C6C6C),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitleSvg(String svgPath, String title) {
    return Row(
      children: [
        SvgPicture.asset(svgPath, width: 20, height: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2B2B2B),
          ),
        ),
      ],
    );
  }

  Widget _chipButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF272942) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF2B2B2B),
          ),
        ),
      ),
    );
  }
}

// ─── Filter calendar ────────────────────────────────────────────────────────────

class _FilterCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final Set<String> selectedDays;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final void Function(String) onDayTap;

  const _FilterCalendar({
    required this.focusedMonth,
    required this.selectedDays,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  static const _dayHeaders = ['SAN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _monthNames = [
    '',
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  static const _shortMonths = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dayLabel(int day) {
    final date = DateTime(focusedMonth.year, focusedMonth.month, day);
    return '${_weekdays[date.weekday - 1]}, $day ${_shortMonths[focusedMonth.month]}';
  }

  @override
  Widget build(BuildContext context) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final now = DateTime.now();
    final isTodayMonth = month == now.month && year == now.year;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onPrevMonth,
                child: const Icon(
                  Icons.chevron_left,
                  color: Color(0xFF272942),
                  size: 24,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month]} $year',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF272942),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF272942),
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: _dayHeaders
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFAAAAAA),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          ...List.generate(6, (week) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: List.generate(7, (weekday) {
                  final dayNum = week * 7 + weekday - firstWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox());
                  }
                  final label = _dayLabel(dayNum);
                  final isSelected = selectedDays.contains(label);
                  final isTodayDay = isTodayMonth && dayNum == now.day;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDayTap(label),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF272942) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isTodayDay && !isSelected
                                ? Border.all(
                                    color: const Color(0xFF272942),
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              '$dayNum',
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF272942),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}
