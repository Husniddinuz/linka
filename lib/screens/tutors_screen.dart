import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton.dart';
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
      name: json['tutor_name'] as String? ?? '',
      image: json['profile_image'] as String?,
      experience: exp,
      score: (json['ielts_score'] as num?)?.toDouble() ?? 0,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
    );
  }

  _TutorCard copyWith({bool? isBookmarked}) => _TutorCard(
        id: id,
        name: name,
        image: image,
        experience: experience,
        score: score,
        isBookmarked: isBookmarked ?? this.isBookmarked,
      );
}

class _TutorFilters {
  final String? gender;
  final List<String> ieltsScores;
  final int? experienceMin;
  final int? experienceMax;
  final String? search;

  const _TutorFilters({
    this.gender,
    this.ieltsScores = const [],
    this.experienceMin,
    this.experienceMax,
    this.search,
  });

  _TutorFilters copyWith({
    String? Function()? gender,
    List<String>? ieltsScores,
    int? Function()? experienceMin,
    int? Function()? experienceMax,
    String? Function()? search,
  }) {
    return _TutorFilters(
      gender: gender != null ? gender() : this.gender,
      ieltsScores: ieltsScores ?? this.ieltsScores,
      experienceMin:
          experienceMin != null ? experienceMin() : this.experienceMin,
      experienceMax:
          experienceMax != null ? experienceMax() : this.experienceMax,
      search: search != null ? search() : this.search,
    );
  }

  /// Number of active non-search filters — shown on the filter button badge.
  int get activeCount =>
      (gender != null ? 1 : 0) +
      ieltsScores.length +
      (experienceMin != null ? 1 : 0);

  bool get hasAny => activeCount > 0 || (search?.isNotEmpty ?? false);

  String toQueryString() {
    final parts = <String>[];
    if (gender != null) parts.add('gender=${Uri.encodeComponent(gender!)}');
    for (final score in ieltsScores) {
      parts.add('ielts_scores=${Uri.encodeComponent(score)}');
    }
    if (experienceMin != null) parts.add('experience_min=$experienceMin');
    if (experienceMax != null) parts.add('experience_max=$experienceMax');
    if (search != null && search!.isNotEmpty) {
      parts.add('search=${Uri.encodeComponent(search!)}');
    }
    if (parts.isEmpty) return '';
    return '?${parts.join('&')}';
  }
}

/// The one-tap quick filters students reach for most.
const _highScoreSet = {'8.0', '8.5', '9.0'};

// ─── Screen ─────────────────────────────────────────────────────────────────────

class TutorsScreen extends StatefulWidget {
  /// True when this screen was pushed as its own route (e.g. from Mock
  /// Tests' "Speaking" button) rather than shown as a bottom-nav tab —
  /// shows a back arrow so the user can return to where they came from.
  final bool showBackButton;

  const TutorsScreen({super.key, this.showBackButton = false});

  @override
  State<TutorsScreen> createState() => _TutorsScreenState();
}

class _TutorsScreenState extends State<TutorsScreen> {
  bool _showSaved = false;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<_TutorCard> _tutors = [];
  List<_TutorCard> _savedTutors = [];
  bool _loading = true;
  bool _loadingSaved = false;
  String? _error;
  _TutorFilters _filters = const _TutorFilters();

  Set<int> _savedTutorIds = {};

  @override
  void initState() {
    super.initState();
    _loadTutors();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTutors({bool showSpinner = true}) async {
    setState(() {
      // On pull-to-refresh keep the current grid visible and let the
      // RefreshIndicator be the only progress affordance.
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      // Fetch tutors and saved tutors in parallel
      final results = await Future.wait([
        ApiService.getList('/tutors/${_filters.toQueryString()}'),
        ApiService.get('/student/saved-tutors/')
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final list = results[0] as List<dynamic>;
      final savedResponse = results[1] as Map<String, dynamic>;
      final savedList = savedResponse['data'] as List<dynamic>? ?? [];
      _savedTutorIds = savedList
          .map((e) => (e as Map<String, dynamic>)['id'] as int? ?? 0)
          .toSet();

      var tutors = list.map((e) {
        final card = _TutorCard.fromJson(e as Map<String, dynamic>);
        return card.copyWith(isBookmarked: _savedTutorIds.contains(card.id));
      }).toList();
      if (_filters.search != null && _filters.search!.isNotEmpty) {
        final q = _filters.search!.toLowerCase();
        tutors =
            tutors.where((t) => t.name.toLowerCase().contains(q)).toList();
      }
      setState(() {
        _tutors = tutors;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadSavedTutors() async {
    setState(() => _loadingSaved = true);
    try {
      final response = await ApiService.get('/student/saved-tutors/');
      final list = response['data'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _savedTutors = list
            .map((e) => _TutorCard.fromJson(e as Map<String, dynamic>))
            .map((t) => t.copyWith(isBookmarked: true))
            .toList();
        _loadingSaved = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _toggleBookmark(_TutorCard tutor) async {
    try {
      if (tutor.isBookmarked) {
        await ApiService.delete('/student/saved-tutors/${tutor.id}/');
      } else {
        await ApiService.post('/student/saved-tutors/', {'tutor_id': tutor.id});
      }
      // Update in main list and saved IDs
      setState(() {
        if (tutor.isBookmarked) {
          _savedTutorIds.remove(tutor.id);
        } else {
          _savedTutorIds.add(tutor.id);
        }
        _tutors = _tutors
            .map((t) =>
                t.id == tutor.id ? t.copyWith(isBookmarked: !t.isBookmarked) : t)
            .toList();
      });
      // Refresh saved list if showing
      if (_showSaved) _loadSavedTutors();
    } catch (e) {
      // Bookmark toggle is best-effort; the next refresh reconciles state.
    }
  }

  void _applyFilters(_TutorFilters next) {
    setState(() => _filters = next);
    _loadTutors();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      final query = value.trim();
      if ((_filters.search ?? '') == query) return;
      _applyFilters(_filters.copyWith(search: () => query.isEmpty ? null : query));
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_filters.search != null) {
      _applyFilters(_filters.copyWith(search: () => null));
    }
  }

  void _clearAll() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _applyFilters(const _TutorFilters());
  }

  void _showFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_TutorFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FilterSheet(filters: _filters),
    );
    if (result != null) {
      // The sheet edits everything except search — carry it over.
      _applyFilters(result.copyWith(search: () => _filters.search));
    }
  }

  // ─── Quick filters ────────────────────────────────────────────────────────

  bool get _highScoreActive =>
      _filters.ieltsScores.toSet().containsAll(_highScoreSet);

  void _toggleHighScore() {
    final scores = _filters.ieltsScores.toSet();
    if (_highScoreActive) {
      scores.removeAll(_highScoreSet);
    } else {
      scores.addAll(_highScoreSet);
    }
    _applyFilters(_filters.copyWith(ieltsScores: scores.toList()..sort()));
  }

  bool get _experiencedActive =>
      _filters.experienceMin == 5 && _filters.experienceMax == null;

  void _toggleExperienced() {
    if (_experiencedActive) {
      _applyFilters(_filters.copyWith(
        experienceMin: () => null,
        experienceMax: () => null,
      ));
    } else {
      _applyFilters(_filters.copyWith(
        experienceMin: () => 5,
        experienceMax: () => null,
      ));
    }
  }

  void _toggleGender(String gender) {
    _applyFilters(_filters.copyWith(
      gender: () => _filters.gender == gender ? null : gender,
    ));
  }

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[
      _QuickChip(
        label: 'IELTS 8+',
        icon: Symbols.military_tech_rounded,
        selected: _highScoreActive,
        onTap: _toggleHighScore,
      ),
      _QuickChip(
        label: '5+ yrs exp',
        icon: Symbols.work_rounded,
        selected: _experiencedActive,
        onTap: _toggleExperienced,
      ),
      _QuickChip(
        label: 'Female',
        selected: _filters.gender == 'Female',
        onTap: () => _toggleGender('Female'),
      ),
      _QuickChip(
        label: 'Male',
        selected: _filters.gender == 'Male',
        onTap: () => _toggleGender('Male'),
      ),
    ];

    // Sheet-set filters the quick chips can't express show as removable chips.
    for (final score in _filters.ieltsScores) {
      if (_highScoreActive && _highScoreSet.contains(score)) continue;
      chips.add(
        _RemovableChip(
          label: 'IELTS $score',
          onRemove: () => _applyFilters(
            _filters.copyWith(
              ieltsScores:
                  _filters.ieltsScores.where((s) => s != score).toList(),
            ),
          ),
        ),
      );
    }

    if (_filters.experienceMin != null && !_experiencedActive) {
      final label = _filters.experienceMax != null
          ? '${_filters.experienceMin}-${_filters.experienceMax} yrs'
          : '${_filters.experienceMin}+ yrs';
      chips.add(
        _RemovableChip(
          label: label,
          onRemove: () => _applyFilters(
            _filters.copyWith(
              experienceMin: () => null,
              experienceMax: () => null,
            ),
          ),
        ),
      );
    }

    if (_filters.hasAny) {
      chips.add(
        GestureDetector(
          onTap: _clearAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Text(
                'Clear all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                  decoration: TextDecoration.underline,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_showSaved) {
      return _SavedTutorsView(
        tutors: _savedTutors,
        loading: _loadingSaved,
        onClose: () => setState(() => _showSaved = false),
        onToggleBookmark: _toggleBookmark,
        onTutorTap: (id) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: id)),
        ),
      );
    }

    final chips = _buildFilterChips(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Grey canvas in light mode so the white cards read as cards.
    final canvas = isDark ? colors.background : colors.surfaceAlt;

    // The hero stays navy in both themes, so status bar icons must be light.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: canvas,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),

            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: chips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => chips[i],
                ),
              ),
            ),

            // Tutors grid
            Expanded(
              child: RefreshIndicator(
                color: Colors.white,
                backgroundColor: colors.brand,
                onRefresh: () => _loadTutors(showSpinner: false),
                child: _buildGridArea(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Navy hero header with overlapping search bar ─────────────────────────

  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;

    final hero = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, gradientEnd],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 42),
          child: Row(
            children: [
              if (widget.showBackButton) ...[
                _FrostedIconButton(
                  icon: Symbols.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Find your tutor',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _loading
                          ? 'Finding IELTS experts…'
                          : '${_tutors.length} ${_tutors.length == 1 ? 'tutor' : 'tutors'} available',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              _FrostedIconButton(
                icon: Symbols.bookmarks_rounded,
                onTap: () {
                  _loadSavedTutors();
                  setState(() => _showSaved = true);
                },
              ),
            ],
          ),
        ),
      ),
    );

    // Search bar overlaps the hero's bottom edge. The trailing SizedBox
    // keeps it inside the Stack's bounds so its taps still register.
    return Stack(
      children: [
        Column(children: [hero, const SizedBox(height: 26)]),
        Positioned(
          left: 20,
          right: 20,
          bottom: 0,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.search_rounded,
                        size: 20,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by name',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: colors.textTertiary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: _clearSearch,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Symbols.close_rounded,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _FilterButton(
                activeCount: _filters.activeCount,
                onTap: () => _showFilterSheet(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridArea(BuildContext context) {
    if (_loading) return const _TutorGridSkeleton();

    if (_tutors.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 90),
          _EmptyState(
            isError: _error != null,
            hasFilters: _filters.hasAny,
            onRetry: _loadTutors,
            onClearFilters: _clearAll,
          ),
        ],
      );
    }

    return _TutorGrid(
      tutors: _tutors,
      onTutorTap: (id) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: id)),
      ),
      onToggleBookmark: _toggleBookmark,
    );
  }
}

// ─── Frosted icon button (for the navy hero) ────────────────────────────────────

class _FrostedIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FrostedIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, opticalSize: 20, color: Colors.white),
      ),
    );
  }
}

// ─── Filter button with badge ───────────────────────────────────────────────────

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? colors.brand : colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? colors.brand : colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Symbols.tune_rounded,
              size: 20,
              opticalSize: 20,
              color: active ? colors.onBrand : colors.textPrimary,
            ),
            if (active)
              Positioned(
                top: -6,
                right: -8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.accentYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      // Fixed navy for contrast on gold in both themes.
                      color: Color(0xFF272942),
                      height: 1.2,
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

// ─── Chips ──────────────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _QuickChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? colors.brand : colors.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? colors.brand : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                opticalSize: 20,
                fill: selected ? 1 : 0,
                color: selected ? colors.onBrand : colors.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colors.onBrand : colors.textPrimary,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _RemovableChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: colors.brand,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onBrand,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Symbols.close_rounded,
              size: 15,
              color: colors.onBrand,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tutor grid ─────────────────────────────────────────────────────────────────

class _TutorGrid extends StatelessWidget {
  final List<_TutorCard> tutors;
  final void Function(int) onTutorTap;
  final void Function(_TutorCard) onToggleBookmark;

  const _TutorGrid({
    required this.tutors,
    required this.onTutorTap,
    required this.onToggleBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = MediaQuery.of(context).size.width >= 600;
        final cols = isTablet ? 3 : 2;
        final cardWidth =
            (constraints.maxWidth - 40 - (cols - 1) * 12) / cols;
        final imageHeight = cardWidth * 2 / 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cardWidth / (imageHeight + 96),
          ),
          itemCount: tutors.length,
          itemBuilder: (_, i) => _TutorGridCard(
            tutor: tutors[i],
            onTap: () => onTutorTap(tutors[i].id),
            onBookmark: () => onToggleBookmark(tutors[i]),
          ),
        );
      },
    );
  }
}

// ─── Tutor grid card ────────────────────────────────────────────────────────────

class _TutorGridCard extends StatelessWidget {
  final _TutorCard tutor;
  final VoidCallback onTap;
  final VoidCallback? onBookmark;
  const _TutorGridCard({
    required this.tutor,
    required this.onTap,
    this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gold = Theme.of(context).brightness == Brightness.dark
        ? colors.accentYellow
        : const Color(0xFFB8860B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo with bookmark overlay
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 2,
                  child: tutor.image != null
                      ? Image.network(
                          tutor.image!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, _, _) =>
                              _ImageFallback(colors: colors),
                        )
                      : _ImageFallback(colors: colors),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onBookmark,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.bookmark_rounded,
                        size: 16,
                        fill: tutor.isBookmarked ? 1 : 0,
                        color: tutor.isBookmarked
                            ? colors.accentYellow
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Symbols.work_rounded,
                          size: 12,
                          opticalSize: 20,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${tutor.experience}+ yrs experience',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _IeltsBadge(score: tutor.score, gold: gold),
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

/// Gold-outlined score badge; a perfect 9.0 gets a solid gold badge with a
/// star so it reads as a different tier at a glance.
class _IeltsBadge extends StatelessWidget {
  final double score;
  final Color gold;
  const _IeltsBadge({required this.score, required this.gold});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (score >= 9) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.accentYellow,
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: colors.accentYellow.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.star_rounded,
              size: 12,
              fill: 1,
              // Fixed navy for contrast on gold in both themes.
              color: Color(0xFF272942),
            ),
            const SizedBox(width: 3),
            Text(
              'IELTS ${score.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Color(0xFF272942),
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accentYellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colors.accentYellow.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        'IELTS ${score % 1 == 0 ? score.toInt() : score}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: gold,
          height: 1.2,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final AppColors colors;
  const _ImageFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        Symbols.person_rounded,
        size: 40,
        fill: 1,
        color: colors.textTertiary,
      ),
    );
  }
}

// ─── Loading skeleton ───────────────────────────────────────────────────────────

class _TutorGridSkeleton extends StatelessWidget {
  const _TutorGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = MediaQuery.of(context).size.width >= 600;
        final cols = isTablet ? 3 : 2;
        final cardWidth =
            (constraints.maxWidth - 40 - (cols - 1) * 12) / cols;
        final imageHeight = cardWidth * 2 / 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cardWidth / (imageHeight + 96),
          ),
          itemCount: 6,
          itemBuilder: (_, _) => Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: imageHeight, borderRadius: 0),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 15, width: 110, borderRadius: 6),
                      SizedBox(height: 8),
                      Skeleton(height: 12, width: 90, borderRadius: 6),
                      SizedBox(height: 10),
                      Skeleton(height: 20, width: 64, borderRadius: 7),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty / error state ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isError;
  final bool hasFilters;
  final VoidCallback onRetry;
  final VoidCallback onClearFilters;

  const _EmptyState({
    required this.isError,
    required this.hasFilters,
    required this.onRetry,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showClear = !isError && hasFilters;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Icon(
            isError
                ? Symbols.wifi_off_rounded
                : Symbols.person_search_rounded,
            size: 32,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isError ? 'Failed to load tutors' : 'No tutors found',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            isError
                ? 'Check your connection and try again.'
                : hasFilters
                    ? 'Try adjusting your search or filters.'
                    : 'New tutors are joining soon — check back later.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        if (isError || showClear) ...[
          const SizedBox(height: 18),
          GestureDetector(
            onTap: isError ? onRetry : onClearFilters,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              decoration: BoxDecoration(
                color: colors.brand,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isError ? 'Retry' : 'Clear filters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onBrand,
                ),
              ),
            ),
          ),
        ],
      ],
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
  static const _ieltsScores = ['6.5', '7.0', '7.5', '8.0', '8.5', '9.0'];
  static const _genders = ['Male', 'Female'];
  static const _experiences = ['1-3 yrs', '3-5 yrs', '5-8 yrs', '8+ years'];

  static const _experienceRanges = {
    '1-3 yrs': (1, 3),
    '3-5 yrs': (3, 5),
    '5-8 yrs': (5, 8),
    '8+ years': (8, null),
  };

  final Set<String> _selectedScores = {};
  String? _selectedGender;
  String? _selectedExperience;

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.filters.gender;
    _selectedScores.addAll(widget.filters.ieltsScores);
    // Restore experience label from min/max
    if (widget.filters.experienceMin != null) {
      for (final entry in _experienceRanges.entries) {
        if (entry.value.$1 == widget.filters.experienceMin &&
            entry.value.$2 == widget.filters.experienceMax) {
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
    } else if (widget.filters.experienceMin != null &&
        _restoredLabelMissing) {
      // A quick-chip range (e.g. 5+) that has no sheet label — keep it
      // unless the user picked a different range.
      expMin = widget.filters.experienceMin;
      expMax = widget.filters.experienceMax;
    }
    return _TutorFilters(
      gender: _selectedGender,
      ieltsScores: _selectedScores.toList()..sort(),
      experienceMin: expMin,
      experienceMax: expMax,
    );
  }

  bool get _restoredLabelMissing {
    if (widget.filters.experienceMin == null) return false;
    for (final entry in _experienceRanges.entries) {
      if (entry.value.$1 == widget.filters.experienceMin &&
          entry.value.$2 == widget.filters.experienceMax) {
        return false;
      }
    }
    return true;
  }

  bool _clearedQuickRange = false;

  void _reset() {
    setState(() {
      _selectedScores.clear();
      _selectedGender = null;
      _selectedExperience = null;
      _clearedQuickRange = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 16),
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  children: [
                    Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _reset,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                _SectionTitle(
                  icon: Symbols.military_tech_rounded,
                  title: 'IELTS score',
                  subtitle: 'Tutor\'s own certified score',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ieltsScores
                      .map(
                        (s) => _SheetChip(
                          label: s,
                          selected: _selectedScores.contains(s),
                          onTap: () => setState(() {
                            if (_selectedScores.contains(s)) {
                              _selectedScores.remove(s);
                            } else {
                              _selectedScores.add(s);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),

                const SizedBox(height: 24),
                Divider(height: 1, color: colors.border),
                const SizedBox(height: 20),

                _SectionTitle(
                  icon: Symbols.work_rounded,
                  title: 'Teaching experience',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _experiences
                      .map(
                        (e) => _SheetChip(
                          label: e,
                          selected: _selectedExperience == e,
                          onTap: () => setState(() {
                            _selectedExperience =
                                _selectedExperience == e ? null : e;
                            _clearedQuickRange = true;
                          }),
                        ),
                      )
                      .toList(),
                ),

                const SizedBox(height: 24),
                Divider(height: 1, color: colors.border),
                const SizedBox(height: 20),

                _SectionTitle(
                  icon: Symbols.person_rounded,
                  title: 'Gender',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _genders
                      .map(
                        (g) => _SheetChip(
                          label: g,
                          icon: g == 'Male'
                              ? Symbols.male_rounded
                              : Symbols.female_rounded,
                          selected: _selectedGender == g,
                          onTap: () => setState(
                            () => _selectedGender =
                                _selectedGender == g ? null : g,
                          ),
                        ),
                      )
                      .toList(),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Sticky apply
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border, width: 0.5)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  var result = _buildFilters();
                  if (_clearedQuickRange && _selectedExperience == null) {
                    result = result.copyWith(
                      experienceMin: () => null,
                      experienceMax: () => null,
                    );
                  }
                  Navigator.pop(context, result);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.brand,
                  foregroundColor: colors.onBrand,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Show tutors',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, opticalSize: 20, color: colors.textPrimary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _SheetChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.brand : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                opticalSize: 20,
                color: selected ? colors.onBrand : colors.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? colors.onBrand : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Saved tutors view ─────────────────────────────────────────────────────────

class _SavedTutorsView extends StatelessWidget {
  final List<_TutorCard> tutors;
  final bool loading;
  final VoidCallback onClose;
  final void Function(_TutorCard) onToggleBookmark;
  final void Function(int) onTutorTap;

  const _SavedTutorsView({
    required this.tutors,
    required this.loading,
    required this.onClose,
    required this.onToggleBookmark,
    required this.onTutorTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? colors.background : colors.surfaceAlt;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;
    return Scaffold(
      backgroundColor: canvas,
      body: Column(
          children: [
            // Navy header band
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.brand, gradientEnd],
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      _FrostedIconButton(
                        icon: Symbols.arrow_back_ios_new_rounded,
                        onTap: onClose,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Saved tutors',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Content
            Expanded(
              child: loading
                  ? const _TutorGridSkeleton()
                  : tutors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colors.border),
                                ),
                                child: Icon(
                                  Symbols.bookmarks_rounded,
                                  size: 30,
                                  color: colors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No saved tutors yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap the bookmark on a tutor card to save them here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _TutorGrid(
                          tutors: tutors,
                          onTutorTap: onTutorTap,
                          onToggleBookmark: onToggleBookmark,
                        ),
            ),
          ],
        ),
    );
  }
}
