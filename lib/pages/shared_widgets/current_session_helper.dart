import 'package:preconnect/api/app_preferences_store.dart';

Future<int?>? _currentSessionSemesterIdInFlight;
int? _currentSessionSemesterIdCache;

Future<int?> resolveCurrentSessionSemesterId() async {
  final parsed = int.tryParse(
    (await AppPreferencesStore().getString('currentSessionSemesterId') ?? '')
        .trim(),
  );
  if (parsed != null && parsed > 0) return parsed;
  return null;
}

Future<int?> preloadCurrentSessionSemesterId({bool forceRefresh = false}) {
  if (!forceRefresh) {
    final cached = _currentSessionSemesterIdCache;
    if (cached != null) return Future<int?>.value(cached);
    final active = _currentSessionSemesterIdInFlight;
    if (active != null) return active;
  }

  final future = resolveCurrentSessionSemesterId().then((semesterId) {
    _currentSessionSemesterIdCache = semesterId;
    return semesterId;
  });
  _currentSessionSemesterIdInFlight = future;
  return future.whenComplete(() {
    if (identical(_currentSessionSemesterIdInFlight, future)) {
      _currentSessionSemesterIdInFlight = null;
    }
  });
}

Future<int> requireCurrentSessionSemesterId() async {
  final semesterId = await preloadCurrentSessionSemesterId();
  if (semesterId == null) {
    throw StateError('Current semester ID is not available.');
  }
  return semesterId;
}
