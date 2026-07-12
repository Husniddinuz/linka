import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _onboardingKey = 'onboarding_completed';
  static const _viewedStoriesKey = 'viewed_stories';
  static const _readNotificationsKey = 'read_notifications';
  static const _viewedNewsKey = 'viewed_news';
  static const _speakingTermsKey = 'speaking_terms_agreed';
  static const _passageHighlightPrefix = 'passage_highlights_';
  static const _readerBgColorKey = 'reading_passage_bg_color';
  static const _readerFontScaleKey = 'reading_passage_font_scale';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // ─── Onboarding ───────────────────────────────────────────────────────

  static Future<bool> isOnboardingCompleted() async {
    final prefs = await _instance;
    return prefs.getBool(_onboardingKey) ?? false;
  }

  static Future<void> setOnboardingCompleted() async {
    final prefs = await _instance;
    await prefs.setBool(_onboardingKey, true);
  }

  // ─── Viewed Stories ───────────────────────────────────────────────────

  static Future<Set<String>> getViewedStories() async {
    final prefs = await _instance;
    return (prefs.getStringList(_viewedStoriesKey) ?? []).toSet();
  }

  static Future<void> markStoryViewed(String storyId) async {
    final prefs = await _instance;
    final list = prefs.getStringList(_viewedStoriesKey) ?? [];
    if (!list.contains(storyId)) {
      list.add(storyId);
      await prefs.setStringList(_viewedStoriesKey, list);
    }
  }

  // ─── Read Notifications ───────────────────────────────────────────────

  static Future<Set<String>> getReadNotifications() async {
    final prefs = await _instance;
    return (prefs.getStringList(_readNotificationsKey) ?? []).toSet();
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final prefs = await _instance;
    final list = prefs.getStringList(_readNotificationsKey) ?? [];
    if (!list.contains(notificationId)) {
      list.add(notificationId);
      await prefs.setStringList(_readNotificationsKey, list);
    }
  }

  static Future<bool> isSpeakingTermsAgreed() async {
    final prefs = await _instance;
    return prefs.getBool(_speakingTermsKey) ?? false;
  }

  static Future<void> setSpeakingTermsAgreed() async {
    final prefs = await _instance;
    await prefs.setBool(_speakingTermsKey, true);
  }

  // ─── Viewed News ──────────────────────────────────────────────────────

  static Future<Set<String>> getViewedNews() async {
    final prefs = await _instance;
    return (prefs.getStringList(_viewedNewsKey) ?? []).toSet();
  }

  static Future<void> markNewsViewed(String newsId) async {
    final prefs = await _instance;
    final list = prefs.getStringList(_viewedNewsKey) ?? [];
    if (!list.contains(newsId)) {
      list.add(newsId);
      await prefs.setStringList(_viewedNewsKey, list);
    }
  }

  // ─── Reading Passage Highlights ───────────────────────────────────────
  //
  // Highlights are stored as the highlighted plain-text phrases themselves
  // (not character offsets), keyed per passage. On render each phrase is
  // located again with a plain substring search — the same approach the
  // writing sample screen uses for examiner annotations — so highlights
  // survive passage HTML/whitespace changes between fetches.

  static Future<List<String>> getPassageHighlights(String passageKey) async {
    final prefs = await _instance;
    return prefs.getStringList('$_passageHighlightPrefix$passageKey') ?? [];
  }

  static Future<void> addPassageHighlight(String passageKey, String text) async {
    final prefs = await _instance;
    final key = '$_passageHighlightPrefix$passageKey';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(text)) {
      list.add(text);
      await prefs.setStringList(key, list);
    }
  }

  static Future<void> removePassageHighlight(String passageKey, String text) async {
    final prefs = await _instance;
    final key = '$_passageHighlightPrefix$passageKey';
    final list = prefs.getStringList(key) ?? [];
    if (list.remove(text)) {
      await prefs.setStringList(key, list);
    }
  }

  // ─── Reading Passage Display Settings ──────────────────────────────────

  static Future<int?> getReaderBackgroundColor() async {
    final prefs = await _instance;
    final value = prefs.getInt(_readerBgColorKey);
    return value;
  }

  static Future<void> setReaderBackgroundColor(int colorValue) async {
    final prefs = await _instance;
    await prefs.setInt(_readerBgColorKey, colorValue);
  }

  static Future<double> getReaderFontScale() async {
    final prefs = await _instance;
    return prefs.getDouble(_readerFontScaleKey) ?? 1.0;
  }

  static Future<void> setReaderFontScale(double scale) async {
    final prefs = await _instance;
    await prefs.setDouble(_readerFontScaleKey, scale);
  }
}
