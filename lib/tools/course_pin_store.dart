import 'package:shared_preferences/shared_preferences.dart';

class CoursePinStore {
  static String _key(String scope) => 'course_pins_$scope';

  static Future<Set<String>> load(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key(scope)) ?? const <String>[];
    return values
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Future<void> save(String scope, Set<String> pins) async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        pins
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    await prefs.setStringList(_key(scope), values);
  }
}
