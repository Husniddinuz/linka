import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Icons an admin can give a Course Reels course or section, by their
/// Material Symbols name. Must match `apps/course_reels/icons.py` on the
/// backend and `courseIcons.jsx` in the admin panel.
const Map<String, IconData> courseIcons = {
  'language': Symbols.language_rounded,
  'school': Symbols.school_rounded,
  'translate': Symbols.translate_rounded,
  'menu_book': Symbols.menu_book_rounded,
  'auto_stories': Symbols.auto_stories_rounded,
  'calculate': Symbols.calculate_rounded,
  'functions': Symbols.functions_rounded,
  'science': Symbols.science_rounded,
  'biotech': Symbols.biotech_rounded,
  'genetics': Symbols.genetics_rounded,
  'bolt': Symbols.bolt_rounded,
  'history_edu': Symbols.history_edu_rounded,
  'public': Symbols.public_rounded,
  'psychology': Symbols.psychology_rounded,
  'code': Symbols.code_rounded,
  'record_voice_over': Symbols.record_voice_over_rounded,
  'mic': Symbols.mic_rounded,
  'forum': Symbols.forum_rounded,
  'edit': Symbols.edit_rounded,
  'edit_note': Symbols.edit_note_rounded,
  'draw': Symbols.draw_rounded,
  'article': Symbols.article_rounded,
  'chrome_reader_mode': Symbols.chrome_reader_mode_rounded,
  'headphones': Symbols.headphones_rounded,
  'hearing': Symbols.hearing_rounded,
  'spellcheck': Symbols.spellcheck_rounded,
  'quiz': Symbols.quiz_rounded,
  'workspace_premium': Symbols.workspace_premium_rounded,
  'emoji_events': Symbols.emoji_events_rounded,
  'military_tech': Symbols.military_tech_rounded,
  'star': Symbols.star_rounded,
  'rocket_launch': Symbols.rocket_launch_rounded,
  'target': Symbols.target_rounded,
  'trending_up': Symbols.trending_up_rounded,
  'lightbulb': Symbols.lightbulb_rounded,
  'timer': Symbols.timer_rounded,
  'flag': Symbols.flag_rounded,
};

/// The glyph for an admin-picked icon name, or [fallback] when it's empty or
/// newer than this build.
IconData courseIcon(
  String name, {
  IconData fallback = Symbols.school_rounded,
}) => courseIcons[name] ?? fallback;
