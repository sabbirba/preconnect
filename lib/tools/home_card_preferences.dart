import 'package:shared_preferences/shared_preferences.dart';

class HomeCardPreferences {
  HomeCardPreferences._();

  static const String _showQuickAccessSectionKey =
      'home_show_quick_access_section';
  static const String _showRamadanCardKey = 'home_show_ramadan_card';
  static const String _showExamCountdownCardKey =
      'home_show_exam_countdown_card';

  static const HomeCardVisibility defaults = HomeCardVisibility(
    showQuickAccessSection: true,
    showRamadanCard: true,
    showExamCountdownCard: true,
  );

  static Future<HomeCardVisibility> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return HomeCardVisibility(
        showQuickAccessSection:
            prefs.getBool(_showQuickAccessSectionKey) ?? true,
        showRamadanCard: prefs.getBool(_showRamadanCardKey) ?? true,
        showExamCountdownCard: prefs.getBool(_showExamCountdownCardKey) ?? true,
      );
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> setShowRamadanCard(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showRamadanCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowExamCountdownCard(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showExamCountdownCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowQuickAccessSection(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showQuickAccessSectionKey, value);
    } catch (_) {}
  }
}

class HomeCardVisibility {
  const HomeCardVisibility({
    required this.showQuickAccessSection,
    required this.showRamadanCard,
    required this.showExamCountdownCard,
  });

  final bool showQuickAccessSection;
  final bool showRamadanCard;
  final bool showExamCountdownCard;
}
