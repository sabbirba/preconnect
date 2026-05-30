import 'dart:async';

import 'package:preconnect/api/calendar.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/ramadan.dart';

class CdnWarmupService {
  CdnWarmupService._();

  static final CdnWarmupService instance = CdnWarmupService._();

  final Map<String, Future<void>> _inflight = <String, Future<void>>{};
  final Set<String> _completed = <String>{};

  Future<void> warmPublicCdnData({bool forceRefresh = false}) async {
    await Future.wait<void>(<Future<void>>[
      _runTask(
        'cdn:seat_status',
        () => SeatStatusService.preload(),
        forceRefresh: forceRefresh,
      ),
      _runTask('cdn:bus', () => BusPage.preload(), forceRefresh: forceRefresh),
      _runTask(
        'cdn:free_labs',
        () => FreeLabsPage.preload(),
        forceRefresh: forceRefresh,
      ),
      _runTask('cdn:campus_map', () async {
        await fetchCampusMapData(forceRefresh: forceRefresh);
      }, forceRefresh: forceRefresh),
      _runTask('cdn:transport_schedule', () async {
        await fetchTransportScheduleUrl(forceRefresh: forceRefresh);
      }, forceRefresh: forceRefresh),
      _runTask('cdn:holiday', () async {
        await HolidayTiming.getTodayStatus(forceRefresh: forceRefresh);
      }, forceRefresh: forceRefresh),
      _runTask('cdn:ramadan_status', () async {
        await RamadanTiming.getRamadanStatus(forceRefresh: forceRefresh);
      }, forceRefresh: forceRefresh),
      _runTask('cdn:notifications_feed', () async {
        await NotificationService().getScraperContentFeed(
          forceRefresh: forceRefresh,
        );
      }, forceRefresh: forceRefresh),
      _runTask('cdn:academic_dates', () async {
        await CalendarService().preloadAcademicDates(
          forceRefresh: forceRefresh,
        );
      }, forceRefresh: forceRefresh),
      _runTask('cdn:exam_map_index', () async {
        await ExamMapService().preloadIndex(forceRefresh: forceRefresh);
      }, forceRefresh: forceRefresh),
      _runTask('cdn:course_prerequisites', () async {
        await ProgressService().preloadCoursePrerequisites();
      }, forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _runTask(
    String key,
    Future<void> Function() task, {
    required bool forceRefresh,
  }) {
    final inFlight = _inflight[key];
    if (inFlight != null) return inFlight;
    if (!forceRefresh && _completed.contains(key)) {
      return Future<void>.value();
    }

    final future = () async {
      try {
        await task();
      } catch (_) {
      } finally {
        _inflight.remove(key);
        _completed.add(key);
      }
    }();
    _inflight[key] = future;
    return future;
  }
}
