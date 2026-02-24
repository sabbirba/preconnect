import 'package:shared_preferences/shared_preferences.dart';

class HomeCardPreferences {
  HomeCardPreferences._();

  static const String _showQuickAccessSectionKey =
      'home_show_quick_access_section';
  static const String _showRamadanCardKey = 'home_show_ramadan_card';
  static const String _showExamCountdownCardKey =
      'home_show_exam_countdown_card';
  static const String _showTodayScheduleKey = 'home_show_today_schedule';
  static const String _showStudentContactCardsKey =
      'home_show_student_contact_cards';

  static const HomeCardVisibility defaults = HomeCardVisibility(
    showQuickAccessSection: true,
    showRamadanCard: true,
    showExamCountdownCard: true,
    showTodaySchedule: true,
    showStudentContactCards: true,
  );

  static Future<HomeCardVisibility> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return HomeCardVisibility(
        showQuickAccessSection:
            prefs.getBool(_showQuickAccessSectionKey) ?? true,
        showRamadanCard: prefs.getBool(_showRamadanCardKey) ?? true,
        showExamCountdownCard: prefs.getBool(_showExamCountdownCardKey) ?? true,
        showTodaySchedule: prefs.getBool(_showTodayScheduleKey) ?? true,
        showStudentContactCards:
            prefs.getBool(_showStudentContactCardsKey) ?? true,
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

  static Future<void> setShowTodaySchedule(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showTodayScheduleKey, value);
    } catch (_) {}
  }

  static Future<void> setShowStudentContactCards(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showStudentContactCardsKey, value);
    } catch (_) {}
  }
}

class HomeCardVisibility {
  const HomeCardVisibility({
    required this.showQuickAccessSection,
    required this.showRamadanCard,
    required this.showExamCountdownCard,
    required this.showTodaySchedule,
    required this.showStudentContactCards,
  });

  final bool showQuickAccessSection;
  final bool showRamadanCard;
  final bool showExamCountdownCard;
  final bool showTodaySchedule;
  final bool showStudentContactCards;
}
