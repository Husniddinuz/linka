import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../services/api_service.dart';
import '../services/course_reels_resume_service.dart';
import '../services/course_reels_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../utils/course_icons.dart';
import 'course_reels_feed_screen.dart';
import 'course_reels_screen.dart' show SavedReelsScreen;
import 'ielts_section_intro_screen.dart';
import 'payment_topup_screen.dart';

/// 250000 → "250 000 UZS".
String _formatUzs(int amount) {
  final digits = amount.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return '$out UZS';
}

/// One section of the course path (e.g. Speaking), as the admin set it up:
/// its icon, price and planned units, plus the units uploaded so far.
class IeltsPart {
  IeltsPart(this.section, this.index, this.lessons);

  final ReelSection section;

  /// Position on the path, bottom (0) to top.
  final int index;

  /// The section's uploaded units, in order.
  final List<ReelLesson> lessons;

  int get id => section.id;
  String get label => section.title;
  IconData get icon => courseIcon(section.icon);
  int get priceUzs => section.priceUzs;
  String get priceLabel => _formatUzs(priceUzs);

  /// The path draws every planned unit, uploaded or not.
  int get unitCount =>
      math.max(1, math.max(section.plannedLessons, lessons.length));

  /// Units finished in a row from the start — what unlocks the next one.
  int get completed {
    var n = 0;
    while (n < lessons.length && lessons[n].progress.completed) {
      n++;
    }
    return n;
  }

  @override
  bool operator ==(Object other) => other is IeltsPart && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A sectioned course (e.g. Linka IELTS) as one game-style path: the first
/// section at the bottom, each section's last unit leading into the next
/// section's banner. The header has two dropdowns: one switches to another
/// sectioned course, the other jumps between sections and follows along as
/// the student scrolls. Sections, icons, prices and unit counts all
/// come from the admin panel.
///
/// Shown inside the Home tab, under the app header and above the bottom
/// nav, rather than pushed as its own route.
class IeltsCourseView extends StatefulWidget {
  const IeltsCourseView({
    super.key,
    required this.courseId,
    required this.onBack,
    required this.onOpenCourse,
  });

  final int courseId;
  final VoidCallback onBack;

  /// Another course picked in the header; the Home tab owns which one is open.
  final ValueChanged<int> onOpenCourse;

  @override
  State<IeltsCourseView> createState() => _IeltsCourseViewState();
}

enum _UnitState { done, current, locked }

class _IeltsCourseViewState extends State<IeltsCourseView>
    with SingleTickerProviderStateMixin {
  static const double _nodeSize = 76;
  static const double _rowHeight = 170;
  static const double _bannerHeight = 64;
  static const double _bannerGap = 170; // banner ↔ neighbouring unit
  static const double _certificateGap = 200;
  static const double _certificateHeight = 200;
  static const double _topPad = 130; // clears the certificate card's top half

  // Space a node takes above / below its centre, so the dashes stop short of
  // it instead of running under the "Unit N" label.
  static const double _unitAbove = _nodeSize / 2 + 8;
  static const double _unitBelow = _nodeSize / 2 + 40;
  static const double _bannerExtent = _bannerHeight / 2 + 8;
  static const double _certificateBelow = _certificateHeight / 2 + 12;

  final ScrollController _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  ReelCourse? _course;
  List<IeltsPart> _parts = const [];

  /// The sectioned courses the header can switch between. Kept across
  /// switches, since each course gets a fresh view.
  static List<ReelCourse> _courses = const [];
  bool _loading = true;
  bool _failed = false;

  // Whether the student has been through a section's intro; unit 1 stays
  // locked until then. Saved on the device, and a section with any progress
  // counts as seen too, so a reinstall or another phone doesn't lock
  // finished units again.
  bool _introSeen(IeltsPart part) =>
      CourseReelsResumeService.introSeen(part.id) ||
      part.lessons.any(
        (l) => l.progress.watched || l.progress.positionSeconds > 0,
      );

  Map<IeltsPart, int> get _completed => {
    for (final p in _parts) p: p.completed,
  };

  // Sections the student can fully open: free, or bought.
  Set<IeltsPart> get _owned => {
    for (final p in _parts)
      if (p.section.owned) p,
  };

  /// A purchase is in flight (including a top-up waiting to be used).
  bool _buying = false;

  /// Dropdown position: 0–3 are the sections, 4 is the certificate.
  int _selected = 0;
  bool _jumping = false;

  /// Distance from the content's bottom edge to each section banner's
  /// centre, then the certificate's — what the dropdown scrolls to. Filled
  /// in by [_layout].
  List<double> _bannerFromBottom = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _course == null;
      _failed = false;
    });
    try {
      final (course, _) = await (
        CourseReelsService.fetchCourse(widget.courseId),
        CourseReelsResumeService.load(),
      ).wait;
      if (!mounted) return;
      final parts = [
        for (final (i, section) in course.sections.indexed)
          IeltsPart(section, i, [
            for (final lesson in course.lessons)
              if (lesson.sectionId == section.id) lesson,
          ]),
      ];
      _loadCourses();
      setState(() {
        _course = course;
        _parts = parts;
        _loading = false;
        _selected = _selected.clamp(0, parts.length);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _course == null;
      });
    }
  }

  /// Fills the course switcher. Failing leaves the last list (or just this
  /// course) in place; the path itself doesn't depend on it.
  Future<void> _loadCourses() async {
    try {
      final courses = await CourseReelsService.fetchSectionedCourses();
      if (!mounted) return;
      setState(() => _courses = courses);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// [i] is the unit index; -1 is the section's intro, which always comes
  /// first.
  _UnitState _state(IeltsPart part, int i) {
    final seen = _introSeen(part);
    if (i < 0) return seen ? _UnitState.done : _UnitState.current;
    if (!seen) return _UnitState.locked;
    final done = _completed[part]!;
    if (i < done) return _UnitState.done;
    if (i == done) return _UnitState.current;
    return _UnitState.locked;
  }

  /// Unit 1 of every section is free; the rest needs the section bought.
  /// The server decides for uploaded units (the section's first one is free
  /// to try); units still to come follow the same rule.
  bool _paywalled(IeltsPart part, int i) {
    if (_owned.contains(part)) return false;
    return i < part.lessons.length ? part.lessons[i].locked : i > 0;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Confirm, then pay from the wallet. When the balance is short, top up
  /// exactly the difference and buy straight after the payment clears.
  Future<void> _buy(IeltsPart part) async {
    if (_buying) return;
    int? balance;
    try {
      balance = await WalletService.getBalance();
    } catch (_) {
      balance = WalletService.cachedBalance;
    }
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BuySectionSheet(part: part, balanceUzs: balance),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _buying = true);
    try {
      await _purchase(part, afterTopUp: false);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _purchase(IeltsPart part, {required bool afterTopUp}) async {
    try {
      await CourseReelsService.buySection(part.id);
      WalletService.getBalance().ignore(); // refresh the cached balance
      if (!mounted) return;
      _snack('${part.label} unlocked — all ${part.unitCount} units are open');
      await _load();
    } on ReelInsufficientBalance catch (short) {
      if (!mounted) return;
      if (afterTopUp) {
        // Topped up, but less than needed (the amount was edited down).
        _snack(
          'Still ${_formatUzs(short.shortfallUzs)} short. '
          'Tap Buy again to top up the rest.',
        );
        return;
      }
      final paid = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentTopUpScreen(
            initialAmount: short.shortfallUzs,
            purpose:
                'Add ${_formatUzs(short.shortfallUzs)} to unlock '
                '${part.label} (${part.priceLabel}). It unlocks as soon as '
                'the payment goes through.',
          ),
        ),
      );
      if (!mounted || paid == null) return;
      await _purchase(part, afterTopUp: true);
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack("Couldn't complete the purchase. Try again.");
    }
  }

  /// Keeps the dropdown label on whichever section fills the middle of the
  /// screen. The list is reversed, so the offset counts up from the bottom.
  void _followScroll() {
    if (_jumping || _bannerFromBottom.isEmpty) return;
    final middle = _scroll.offset + _scroll.position.viewportDimension / 2;
    var active = 0;
    for (var k = 0; k < _bannerFromBottom.length; k++) {
      if (_bannerFromBottom[k] <= middle) active = k;
    }
    // The certificate sits too close to the top for the middle of the screen
    // to ever pass it, so reaching the top counts as being there.
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 1) {
      active = _bannerFromBottom.length - 1;
    }
    if (active != _selected) setState(() => _selected = active);
  }

  Future<void> _jumpTo(int stop) async {
    setState(() => _selected = stop);
    if (!_scroll.hasClients || _bannerFromBottom.isEmpty) return;
    // A banner sits just above the bottom edge, its units climbing above it;
    // the certificate is at the very top, which the clamp lands on.
    final target = _bannerFromBottom[stop] - _bannerHeight / 2 - 24;
    _jumping = true;
    await _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
    _jumping = false;
  }

  int get _sectionsFinished =>
      _parts.where((p) => p.completed >= p.unitCount).length;

  /// Needs every section bought and every unit in it finished.
  bool get _certificateEarned =>
      _parts.isNotEmpty &&
      _owned.length == _parts.length &&
      _sectionsFinished == _parts.length;

  Future<void> _openCertificate() async {
    final result = await showModalBottomSheet<(_CertificateAction, IeltsPart?)>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CertificateSheet(parts: _parts, owned: _owned),
    );
    if (!mounted || result == null) return;
    final (action, part) = result;
    switch (action) {
      case _CertificateAction.buy:
        _buy(part!);
      case _CertificateAction.continueSection:
        _jumpTo(part!.index);
      case _CertificateAction.claim:
        // Certificate issuing isn't built yet.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Certificates coming soon')),
          );
    }
  }

  Future<void> _openIntro(IeltsPart part) async {
    final started = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => IeltsSectionIntroScreen(
          part: part,
          unitCount: part.unitCount,
          owned: _owned.contains(part),
          priceLabel: part.priceLabel,
        ),
      ),
    );
    if (!mounted || started != true) return;
    await CourseReelsResumeService.markIntroSeen(part.id);
    if (mounted) setState(() {});
  }

  void _openUnit(IeltsPart part, int i) {
    if (i < 0) {
      _openIntro(part);
      return;
    }
    if (_paywalled(part, i)) {
      _buy(part);
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (_state(part, i) == _UnitState.locked) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _introSeen(part)
                ? 'Finish ${part.label} · Unit ${_completed[part]! + 1} first'
                : 'Start with the ${part.label} intro',
          ),
        ),
      );
      return;
    }
    if (i >= part.lessons.length) {
      // Planned in the admin panel but not uploaded yet.
      messenger.showSnackBar(
        SnackBar(content: Text('${part.label} · Unit ${i + 1} — coming soon')),
      );
      return;
    }
    _openLesson(part.lessons[i]);
  }

  Future<void> _openLesson(ReelLesson lesson) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseReelsFeedScreen(
          courseId: widget.courseId,
          initialLessonId: lesson.id,
        ),
      ),
    );
    // Watching and practice move the path along.
    if (mounted) _load();
  }

  Future<void> _openSaved() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedReelsScreen()),
    );
    if (mounted) _load();
  }

  /// Places every banner, unit and the certificate, bottom to top.
  _Layout _layout(double width, double bottomInset) {
    final amplitude = math.min(width * 0.26, 110.0);
    final nodes = <_Node>[];
    var b = 40 + bottomInset + _bannerHeight / 2; // distance from bottom
    final banners = <double>[];

    for (final part in _parts) {
      banners.add(b);
      nodes.add(_Node.banner(part, width / 2, b));
      // Alternate the swing so consecutive sections don't look identical.
      final side = part.index.isEven ? 1.0 : -1.0;
      // Stop 0 is the intro (unit index -1), straight above the banner.
      for (var stop = 0; stop <= part.unitCount; stop++) {
        b += stop == 0 ? _bannerGap : _rowHeight;
        final swing = math.sin(stop * math.pi / 4) * side;
        nodes.add(_Node.unit(part, stop - 1, width / 2 + swing * amplitude, b));
      }
      b += part == _parts.last ? _certificateGap : _bannerGap;
    }
    banners.add(b);
    nodes.add(_Node.certificate(width / 2, b));
    final height = b + _topPad;
    return _Layout(nodes: nodes, banners: banners, height: height);
  }

  /// Back button over a loading spinner, an error with retry, or an empty
  /// course — anything short of a path to draw.
  Widget _placeholder(BuildContext context) {
    final c = context.colors;
    final Widget body;
    if (_loading) {
      body = const CircularProgressIndicator();
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _failed ? Symbols.wifi_off_rounded : Symbols.construction_rounded,
              size: 48,
              color: c.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              _failed
                  ? "Couldn't load the course"
                  : 'This course is being prepared. Check back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Symbols.arrow_back_rounded, color: c.textPrimary),
              ),
            ],
          ),
        ),
        Expanded(child: Center(child: body)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading || _failed || _parts.isEmpty) return _placeholder(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Symbols.arrow_back_rounded, color: c.textPrimary),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _CourseDropdown(
                        current: _course!,
                        courses: _courses,
                        onSelected: (id) {
                          if (id != widget.courseId) widget.onOpenCourse(id);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _SectionDropdown(
                        entries: [
                          for (final part in _parts)
                            _DropdownEntry(
                              icon: part.icon,
                              label: part.label,
                              progress: _owned.contains(part)
                                  ? '${part.completed}/${part.unitCount}'
                                  : null,
                            ),
                          _DropdownEntry(
                            icon: Symbols.workspace_premium_rounded,
                            label: 'Certificate',
                            progress: _certificateEarned ? 'Earned' : null,
                          ),
                        ],
                        selected: _selected,
                        onSelected: _jumpTo,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Saved lessons',
                onPressed: _openSaved,
                icon: Icon(Symbols.bookmark_rounded, color: c.textPrimary),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // The bottom nav already clears the home indicator.
              final layout = _layout(width, 0);
              _bannerFromBottom = layout.banners;
              final h = layout.height;
              double top(_Node n) => h - n.fromBottom; // y from the content top

              return SingleChildScrollView(
                controller: _scroll,
                // Offset 0 is the bottom, where Speaking · Unit 1 is.
                reverse: true,
                child: SizedBox(
                  width: width,
                  height: h,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DashedPathPainter(
                            segments: [
                              for (var i = 0; i + 1 < layout.nodes.length; i++)
                                _segment(
                                  layout.nodes[i],
                                  layout.nodes[i + 1],
                                  h,
                                ),
                            ],
                            done: c.accentYellow,
                            todo: c.textTertiary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      for (final n in layout.nodes)
                        switch (n.kind) {
                          _NodeKind.banner => Positioned(
                            left: 0,
                            right: 0,
                            top: top(n) - _bannerHeight / 2,
                            height: _bannerHeight,
                            child: Center(
                              child: _SectionBanner(
                                part: n.part!,
                                done: n.part!.completed,
                                total: n.part!.unitCount,
                                owned: _owned.contains(n.part),
                                onBuy: () => _buy(n.part!),
                              ),
                            ),
                          ),
                          _NodeKind.unit => Positioned(
                            left: n.x - 60,
                            top: top(n) - (_nodeSize + 24) / 2,
                            width: 120,
                            child: _UnitSquare(
                              label: n.index < 0
                                  ? 'Intro'
                                  : 'Unit ${n.index + 1}',
                              icon: n.index < 0
                                  ? Symbols.lightbulb_rounded
                                  : Symbols.play_arrow_rounded,
                              state: _state(n.part!, n.index),
                              free: n.index == 0 && !_owned.contains(n.part),
                              pulse: _pulse,
                              size: _nodeSize,
                              onTap: () => _openUnit(n.part!, n.index),
                            ),
                          ),
                          _NodeKind.certificate => Positioned(
                            left: 0,
                            right: 0,
                            top: top(n) - _certificateHeight / 2,
                            height: _certificateHeight,
                            child: Center(
                              child: _CertificateCard(
                                bought: _owned.length,
                                finished: _sectionsFinished,
                                total: _parts.length,
                                onTap: _openCertificate,
                              ),
                            ),
                          ),
                        },
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// One dashed link, from the top of [lower] to the bottom of [upper].
  _Segment _segment(_Node lower, _Node upper, double height) {
    double above(_Node n) => switch (n.kind) {
      _NodeKind.unit => _unitAbove,
      _NodeKind.banner => _bannerExtent,
      _NodeKind.certificate => 0,
    };
    double below(_Node n) => switch (n.kind) {
      _NodeKind.unit => _unitBelow,
      _NodeKind.banner => _bannerExtent,
      _NodeKind.certificate => _certificateBelow,
    };
    // Green once the student has moved past the lower end.
    final done = switch (lower.kind) {
      _NodeKind.unit => _state(lower.part!, lower.index) == _UnitState.done,
      _NodeKind.banner => _introSeen(lower.part!),
      _NodeKind.certificate => false,
    };
    return _Segment(
      from: Offset(lower.x, height - lower.fromBottom - above(lower)),
      to: Offset(upper.x, height - upper.fromBottom + below(upper)),
      done: done,
    );
  }
}

enum _NodeKind { banner, unit, certificate }

class _Node {
  _Node.banner(this.part, this.x, this.fromBottom)
    : kind = _NodeKind.banner,
      index = -1;
  _Node.unit(this.part, this.index, this.x, this.fromBottom)
    : kind = _NodeKind.unit;
  _Node.certificate(this.x, this.fromBottom)
    : kind = _NodeKind.certificate,
      part = null,
      index = -1;

  final _NodeKind kind;
  final IeltsPart? part;
  final int index;
  final double x;
  final double fromBottom;
}

class _Layout {
  const _Layout({
    required this.nodes,
    required this.banners,
    required this.height,
  });

  final List<_Node> nodes;
  final List<double> banners;
  final double height;
}

class _Segment {
  const _Segment({required this.from, required this.to, required this.done});

  final Offset from;
  final Offset to;
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is _Segment &&
      other.from == from &&
      other.to == to &&
      other.done == done;

  @override
  int get hashCode => Object.hash(from, to, done);
}

class _DropdownEntry {
  const _DropdownEntry({
    required this.icon,
    required this.label,
    this.progress,
  });

  final IconData icon;
  final String label;

  /// e.g. "3/10"; null shows a lock instead.
  final String? progress;
}

/// Switches the path to another sectioned course. Always a dropdown, even
/// while this is the only course, so students know where to find more.
class _CourseDropdown extends StatelessWidget {
  const _CourseDropdown({
    required this.current,
    required this.courses,
    required this.onSelected,
  });

  final ReelCourse current;
  final List<ReelCourse> courses;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The list may still be loading (or have failed); the open course is
    // always an option.
    final options = [
      if (!courses.any((course) => course.id == current.id)) current,
      ...courses,
    ];
    return PopupMenuButton<int>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: c.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final course in options)
          PopupMenuItem(
            value: course.id,
            height: 52,
            child: _MenuRow(
              icon: courseIcon(course.icon),
              label: course.title,
              selected: course.id == current.id,
            ),
          ),
      ],
      child: _HeaderPill(icon: courseIcon(current.icon), label: current.title),
    );
  }
}

class _SectionDropdown extends StatelessWidget {
  const _SectionDropdown({
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  final List<_DropdownEntry> entries;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = entries[selected];
    return PopupMenuButton<int>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: c.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final (i, e) in entries.indexed)
          PopupMenuItem(
            value: i,
            height: 52,
            child: _MenuRow(
              icon: e.icon,
              label: e.label,
              selected: i == selected,
              trailing: e.progress != null
                  ? Text(
                      e.progress!,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary,
                      ),
                    )
                  : Icon(Symbols.lock_rounded, size: 16, color: c.textTertiary),
            ),
          ),
      ],
      child: _HeaderPill(
        icon: current.icon,
        label: current.label,
        labelKey: ValueKey(selected),
      ),
    );
  }
}

/// The closed state of a header dropdown: icon, label, chevron.
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label, this.labelKey});

  final IconData icon;
  final String label;

  /// Set to cross-fade the label when it changes.
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c.textPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Symbols.expand_more_rounded, size: 22, color: c.textPrimary),
        ],
      ),
    );
  }
}

/// One option in a header dropdown's menu.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.selected,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: c.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
          Icon(
            Symbols.check_rounded,
            size: 18,
            color: selected ? c.textPrimary : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// Opens each section on the path, and links it to the one before.
class _SectionBanner extends StatelessWidget {
  const _SectionBanner({
    required this.part,
    required this.done,
    required this.total,
    required this.owned,
    required this.onBuy,
  });

  final IeltsPart part;
  final int done;
  final int total;
  final bool owned;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, owned ? 18 : 10, 8),
      decoration: BoxDecoration(
        color: c.success,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color.lerp(c.success, Colors.black, 0.28)!,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(part.icon, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SECTION ${part.index + 1}',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                part.label,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          if (owned)
            Text(
              '$done/$total',
              style: const TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            )
          else
            GestureDetector(
              onTap: onBuy,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.lock_open_rounded, size: 14, color: c.success),
                    const SizedBox(width: 4),
                    Text(
                      part.priceLabel,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: c.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The last stop: the certificate. Earned by buying every section and
/// finishing all of their units.
class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.bought,
    required this.finished,
    required this.total,
    required this.onTap,
  });

  final int bought;
  final int finished;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final earned = bought == total && finished == total;
    final fill = earned ? c.accentYellow : c.surfaceAlt;
    final ink = earned ? Colors.white : c.textPrimary;
    final soft = earned ? Colors.white.withValues(alpha: 0.8) : c.textSecondary;

    Widget requirement(String text, int have) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            have == total
                ? Symbols.check_circle_rounded
                : Symbols.radio_button_unchecked_rounded,
            size: 16,
            fill: have == total ? 1 : 0,
            color: have == total && !earned ? c.success : soft,
          ),
          const SizedBox(width: 6),
          Text(
            '$text $have/$total',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: soft,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Certificate, ${earned ? 'earned' : 'locked'}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 250,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(24),
            border: earned ? null : Border.all(color: c.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(fill, Colors.black, 0.28)!,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Symbols.workspace_premium_rounded,
                    size: 52,
                    fill: earned ? 1 : 0,
                    color: earned ? Colors.white : c.accentYellow,
                  ),
                  if (!earned)
                    Positioned(
                      right: -6,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.lock_rounded,
                          size: 14,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'FINAL STEP',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: soft,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'IELTS Certificate',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              requirement('Sections bought', bought),
              requirement('Sections finished', finished),
            ],
          ),
        ),
      ),
    );
  }
}

/// What's between the student and the certificate, with a way forward:
/// buy the missing sections, keep learning, or claim it.
class _CertificateSheet extends StatelessWidget {
  const _CertificateSheet({required this.parts, required this.owned});

  final List<IeltsPart> parts;
  final Set<IeltsPart> owned;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allBought = owned.length == parts.length;
    final allFinished = parts.every((p) => p.completed >= p.unitCount);
    final earned = allBought && allFinished;
    final firstUnbought = parts.where((p) => !owned.contains(p)).firstOrNull;
    final firstUnfinished = parts
        .where((p) => p.completed < p.unitCount)
        .firstOrNull;

    final (String cta, _CertificateAction action, IeltsPart? target) = earned
        ? ('Get my certificate', _CertificateAction.claim, null)
        : !allBought
        ? (
            'Unlock ${firstUnbought!.label}',
            _CertificateAction.buy,
            firstUnbought,
          )
        : (
            'Continue ${firstUnfinished!.label}',
            _CertificateAction.continueSection,
            firstUnfinished,
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(
              Symbols.workspace_premium_rounded,
              size: 64,
              fill: 1,
              color: c.accentYellow,
            ),
            const SizedBox(height: 12),
            Text(
              earned ? 'You did it!' : 'Earn your IELTS certificate',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              earned
                  ? 'Every section is complete.'
                  : 'Unlock every section and finish all of its units.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            for (final part in parts)
              _CertificateRow(
                part: part,
                owned: owned.contains(part),
                done: part.completed,
                total: part.unitCount,
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (action, target)),
                style: FilledButton.styleFrom(
                  backgroundColor: earned ? c.accentYellow : c.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  cta,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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

enum _CertificateAction { buy, continueSection, claim }

class _CertificateRow extends StatelessWidget {
  const _CertificateRow({
    required this.part,
    required this.owned,
    required this.done,
    required this.total,
  });

  final IeltsPart part;
  final bool owned;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final finished = owned && done >= total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(part.icon, size: 19, color: c.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              part.label,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          Text(
            !owned
                ? 'Not bought'
                : finished
                ? 'Finished'
                : '$done/$total units',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: finished ? c.success : c.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            finished
                ? Symbols.check_circle_rounded
                : owned
                ? Symbols.radio_button_unchecked_rounded
                : Symbols.lock_rounded,
            size: 20,
            fill: finished ? 1 : 0,
            color: finished ? c.success : c.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _UnitSquare extends StatelessWidget {
  const _UnitSquare({
    required this.label,
    required this.icon,
    required this.state,
    required this.free,
    required this.pulse,
    required this.size,
    required this.onTap,
  });

  final String label;

  /// Face of a playable stop — play for units, a bulb for the intro.
  final IconData icon;
  final _UnitState state;

  /// The section isn't bought and this is its free first unit.
  final bool free;
  final Animation<double> pulse;
  final double size;
  final VoidCallback onTap;

  static const double _radius = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fill;
    final Widget face;
    switch (state) {
      case _UnitState.done:
        fill = c.accentYellow;
        face = const Icon(
          Symbols.check_rounded,
          size: 38,
          weight: 700,
          color: Colors.white,
        );
      case _UnitState.current:
        fill = c.success;
        face = Icon(icon, fill: 1, size: 42, color: Colors.white);
      case _UnitState.locked:
        fill = c.surfaceAlt;
        face = Icon(Symbols.lock_rounded, size: 30, color: c.textTertiary);
    }

    final square = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          // The "3D" lip under each unit.
          BoxShadow(
            color: Color.lerp(fill, Colors.black, 0.28)!,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: face,
    );

    final current = state == _UnitState.current;
    return Semantics(
      button: true,
      label: '$label, ${state.name}${free ? ', free' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size + 24,
              height: size + 24,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (current)
                    AnimatedBuilder(
                      animation: pulse,
                      builder: (context, _) => Container(
                        width: size + 24 * pulse.value,
                        height: size + 24 * pulse.value,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            _radius + 12 * pulse.value,
                          ),
                          border: Border.all(
                            color: fill.withValues(
                              alpha: (1 - pulse.value) * 0.6,
                            ),
                            width: 4,
                          ),
                        ),
                      ),
                    ),
                  square,
                  if (free) Positioned(right: 2, bottom: 6, child: _FreeTag()),
                  if (current)
                    Positioned(
                      top: -34,
                      child: _StartBubble(color: fill, bounce: pulse),
                    ),
                ],
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current ? c.textPrimary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedPathPainter extends CustomPainter {
  _DashedPathPainter({
    required this.segments,
    required this.done,
    required this.todo,
  });

  final List<_Segment> segments;
  final Color done;
  final Color todo;

  static const double _dash = 2; // with round caps each dash reads as a dot
  static const double _gap = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    for (final s in segments) {
      final a = s.from;
      final b = s.to;
      final mid = (b.dy - a.dy) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy + mid, b.dx, b.dy - mid, b.dx, b.dy);
      paint.color = s.done ? done : todo;
      for (final PathMetric metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += _dash + _gap) {
          canvas.drawPath(
            metric.extractPath(d, math.min(d + _dash, metric.length)),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPathPainter old) =>
      old.done != done ||
      old.todo != todo ||
      old.segments.length != segments.length ||
      !Iterable.generate(
        segments.length,
      ).every((i) => old.segments[i] == segments[i]);
}

/// Duolingo's bobbing "START" tag over the unit to play next.
class _StartBubble extends StatelessWidget {
  const _StartBubble({required this.color, required this.bounce});

  final Color color;
  final Animation<double> bounce;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: bounce,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -4 * math.sin(bounce.value * math.pi)),
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 2),
        ),
        child: Text(
          'START',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _FreeTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.accentYellow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.background, width: 2),
      ),
      child: const Text(
        'FREE',
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 10,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// What buying a section gets you, and the button to do it. Pops `true`
/// when the student taps buy.
class _BuySectionSheet extends StatelessWidget {
  const _BuySectionSheet({required this.part, required this.balanceUzs});

  final IeltsPart part;

  /// Wallet balance, or null when it couldn't be read.
  final int? balanceUzs;

  /// Null when unknown — the server has the final say either way.
  bool? get _covered =>
      balanceUzs == null ? null : balanceUzs! >= part.priceUzs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget perk(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.success,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Color.lerp(c.success, Colors.black, 0.28)!,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(part.icon, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              'Unlock ${part.label}',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Unit 1 is free. Buy the section to open the rest.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            perk(
              Symbols.lock_open_rounded,
              'Units 2–${part.unitCount} of ${part.label}',
            ),
            perk(
              Symbols.shopping_bag_rounded,
              'One-time payment for this section only',
            ),
            if (balanceUzs != null)
              perk(
                Symbols.account_balance_wallet_rounded,
                _covered!
                    ? 'Paid from your balance (${_formatUzs(balanceUzs!)})'
                    : 'Your balance is ${_formatUzs(balanceUzs!)} — top up '
                          '${_formatUzs(part.priceUzs - balanceUzs!)} and it '
                          'unlocks right after',
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: c.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _covered == false
                      ? 'Top up & buy'
                      : 'Buy for ${part.priceLabel}',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not now',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
