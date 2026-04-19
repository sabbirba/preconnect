import 'package:preconnect/api/app_preferences_store.dart';

Future<int?> resolveCurrentSessionSemesterId() async {
  final parsed = int.tryParse(
    (await AppPreferencesStore().getString('currentSessionSemesterId') ?? '')
        .trim(),
  );
  if (parsed != null && parsed > 0) return parsed;
  return null;
}
