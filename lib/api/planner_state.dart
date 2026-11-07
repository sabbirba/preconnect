import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:preconnect/api/planner_store.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/api/seat_stream.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/routine_clash.dart';
import 'package:preconnect/tools/string_utils.dart';

class PlannerController extends ChangeNotifier {
  PlannerController({SeatStatusService? service, PlannerStore? store})
    : _service = service ?? SeatStatusService(),
      _store = store ?? PlannerStore.instance;

  static final PlannerController instance = PlannerController();

  Future<void>? _loadOnce;
  Future<void>? _restoreOnce;

  final SeatStatusService _service;
  final PlannerStore _store;

  Map<int, SeatStatusDetailsResponse> _sections =
      const <int, SeatStatusDetailsResponse>{};
  final List<String> _wishlist = <String>[];
  final Map<String, int> _picks = <String, int>{};
  bool _disposed = false;

  List<SeatStatusDetailsResponse> get pickedSections {
    final list = <SeatStatusDetailsResponse>[
      for (final id in _picks.values) ?_sections[id],
    ]..sort((a, b) => compareNaturalText(a.courseCode, b.courseCode));
    return list;
  }

  bool isPlanned(String courseCode, int sectionId) =>
      _picks[planCourseKey(courseCode)] == sectionId;

  Future<void> plan(String courseCode, int sectionId) async {
    await _restore();
    final key = planCourseKey(courseCode);
    if (key.isEmpty) return;
    final addedCourse = !_wishlist.contains(key);
    if (addedCourse) _wishlist.add(key);
    _picks[key] = sectionId;
    _notify();
    if (addedCourse) await _store.saveWishlist(_wishlist);
    await _store.savePicks(_picks);
  }

  Future<void> removeFromWishlist(String code) async {
    await _restore();
    final key = planCourseKey(code);
    if (!_wishlist.remove(key)) return;
    final unpicked = _picks.remove(key) != null;
    _notify();
    await _store.saveWishlist(_wishlist);
    if (unpicked) await _store.savePicks(_picks);
  }

  Future<void> load() => _loadOnce ??= _load().catchError((Object error) {
    _loadOnce = null;
    throw error;
  });

  Future<void> _restore() =>
      _restoreOnce ??= _restoreSaved().catchError((Object error) {
        _restoreOnce = null;
        throw error;
      });

  Future<void> _restoreSaved() async {
    final results = await Future.wait<Object?>([
      _store.loadWishlist(),
      _store.loadPicks(),
    ]);
    _wishlist
      ..clear()
      ..addAll(results[0]! as List<String>);
    _picks
      ..clear()
      ..addAll(results[1]! as Map<String, int>);
  }

  Future<void> _load() async {
    await _restore();
    final cached = await _service.loadCachedDetails();
    if (cached != null && cached.isNotEmpty) _applySections(cached);
    _notify();
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      _applySections(await _service.fetchRealtimeSections());
      if (_repairPicks()) await _store.savePicks(_picks);
    } catch (error) {
      unawaited(AppLog.write('Planner sections load failed: $error'));
    } finally {
      _notify();
    }
  }

  void _applySections(Map<int, SeatStatusDetailsResponse> details) {
    _sections = Map<int, SeatStatusDetailsResponse>.of(details);
  }

  bool _repairPicks() {
    if (_sections.isEmpty) return false;
    final stale = [
      for (final entry in _picks.entries)
        if (!_sections.containsKey(entry.value)) entry.key,
    ];
    for (final code in stale) {
      _picks.remove(code);
      final replacement = bestSectionFor([
        for (final section in _sections.values)
          if (planCourseKey(section.courseCode) == code) section,
      ], pickedSections);
      if (replacement != null) _picks[code] = replacement.sectionId;
    }
    return stale.isNotEmpty;
  }

  void applySeatCounts(List<SeatCount> counts) {
    if (counts.isEmpty || _sections.isEmpty) return;
    var changed = false;
    for (final count in counts) {
      final current = _sections[count.sectionId];
      if (current == null) continue;
      final capacity = count.capacity ?? current.capacity;
      if (count.consumed == current.consumedSeat &&
          capacity == current.capacity) {
        continue;
      }
      changed = true;
      _sections[count.sectionId] = current.withSeats(
        consumed: count.consumed,
        total: capacity,
      );
    }
    if (changed) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
