import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/materials.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/sse_client.dart';
import 'package:preconnect/tools/storage_keys.dart';

class DatasetSync {
  DatasetSync._();
  static final DatasetSync instance = DatasetSync._();

  static const String manifestUrl =
      '${ApiConfig.realtimeApiBase}/sync/manifest';
  static const String streamUrl = '${ApiConfig.realtimeApiBase}/sync/stream';
  static const int parallelDownloads = 4;
  static const List<Duration> staleRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];
  static const Duration lateRetryDelay = Duration(seconds: 65);
  static const String _versionsKey = 'dataset_versions_v1';

  static const Map<String, String> datasetUrls = <String, String>{
    'announcements': ApiConfig.announcementFeedUrl,
    'news': ApiConfig.newsFeedUrl,
    'academic-dates': ApiConfig.academicDatesUrl,
    'holiday': ApiConfig.holidayStatusUrl,
    'ramadan': ApiConfig.ramadanStatusUrl,
    'course-prerequisites': ApiConfig.coursePrerequisitesUrl,
    'exammap': ApiConfig.examMapIndexUrl,
    'map': ApiConfig.campusMapUrl,
    'transport': ApiConfig.transportUrl,
    'dspace': ApiConfig.dspaceDataUrl,
    'materials': ApiConfig.materialsIndexUrl,
  };

  static const Map<String, String> _refreshReasons = <String, String>{
    'announcements': 'notifications',
    'news': 'notifications',
    'academic-dates': 'holiday',
    'holiday': 'holiday',
    'exammap': 'exam_schedule',
    'course-prerequisites': 'prerequisites',
    'materials': 'materials',
  };

  late final SseClient _live = SseClient(
    name: 'Sync',
    request: () async => http.Request('GET', Uri.parse(streamUrl)),
    onEvent: (_, data) => unawaited(applyVersions(decodeVersions(data))),
    silence: const Duration(seconds: 20),
  );
  Future<void>? _manifestCheck;
  Timer? _lateRetry;
  Future<void> _versionQueue = Future<void>.value();

  void startLive() {
    if (!kIsWeb) _live.start();
  }

  void stopLive() => _live.stop();

  Future<void> checkManifest() {
    return _manifestCheck ??= ApiClient()
        .tryPublicJson(manifestUrl, cacheDuration: Duration.zero)
        .then((payload) => applyVersions(versionsFrom(payload)))
        .whenComplete(() => _manifestCheck = null);
  }

  Future<void> applyPush(Map<String, dynamic> data) async {
    try {
      final versions = decodeVersions('${data['manifest'] ?? ''}');
      await (versions.isEmpty ? checkManifest() : applyVersions(versions));
    } catch (error) {
      unawaited(AppLog.write('Push sync failed: $error'));
    }
  }

  static Map<String, String> versionsFrom(Object? payload) {
    if (payload case {'datasets': final Map<dynamic, dynamic> datasets}) {
      return <String, String>{
        for (final entry in datasets.entries)
          if (entry.value case {
            'version': final String version,
          } when version.isNotEmpty)
            '${entry.key}': version,
      };
    }
    return const <String, String>{};
  }

  static Map<String, String> decodeVersions(String raw) {
    try {
      return versionsFrom(jsonDecode(raw));
    } catch (_) {
      return const <String, String>{};
    }
  }

  static List<String> changedDatasets(
    Map<String, String> remote,
    Map<String, String> known,
  ) => <String>[
    for (final entry in remote.entries)
      if (datasetUrls.containsKey(entry.key) && known[entry.key] != entry.value)
        entry.key,
  ];

  static String compactEtag(String? etag) =>
      (etag ?? '').replaceFirst(RegExp(r'^W/'), '').replaceAll('"', '').trim();

  static bool isFreshResponse(Map<String, String> headers, String version) =>
      compactEtag(headers['etag']) == version;

  Future<void> applyVersions(Map<String, String> remote) {
    if (remote.isEmpty) return Future<void>.value();
    final queued = _versionQueue.then((_) => _applyVersions(remote));
    _versionQueue = queued.catchError((Object _) {});
    return queued;
  }

  Future<void> _applyVersions(Map<String, String> remote) async {
    final known = await _knownVersions();
    final changed = changedDatasets(remote, known);
    if (changed.isEmpty) return;
    final fresh = <String>{};
    await runInParallel(changed, parallelDownloads, (dataset) async {
      if (await _download(dataset, remote[dataset]!)) fresh.add(dataset);
    });
    _retryLater(<String, String>{
      for (final dataset in changed)
        if (!fresh.contains(dataset)) dataset: remote[dataset]!,
    });
    if (fresh.isEmpty) return;
    await _refreshOwners(fresh);
    for (final reason in fresh.map((d) => _refreshReasons[d] ?? 'datasets')) {
      RefreshBus.instance.notify(reason: reason);
    }
    await RepositoryCache.instance.writeJson(_versionsKey, <String, String>{
      ...known,
      for (final dataset in fresh) dataset: remote[dataset]!,
    });
  }

  void _retryLater(Map<String, String> stale) {
    if (stale.isEmpty) return;
    _lateRetry?.cancel();
    _lateRetry = Timer(lateRetryDelay, () => unawaited(applyVersions(stale)));
  }

  Future<Map<String, String>> _knownVersions() async {
    final saved = await RepositoryCache.instance.readJsonMap(_versionsKey);
    return <String, String>{
      for (final entry in (saved ?? const <String, dynamic>{}).entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  Future<bool> _download(String dataset, String version) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await ApiClient().publicGet(
          datasetUrls[dataset]!,
          cacheDuration: Duration.zero,
        );
        if (isFreshResponse(response.headers, version)) return true;
        if (compactEtag(response.headers['etag']).isEmpty) return false;
      } catch (error) {
        unawaited(AppLog.write('Dataset refresh failed ($dataset): $error'));
        return false;
      }
      if (attempt == staleRetryDelays.length) return false;
      await Future<void>.delayed(staleRetryDelays[attempt]);
    }
  }

  Future<void> _refreshOwners(Set<String> datasets) async {
    final owners = <String, Future<void> Function()>{
      for (final dataset in datasets)
        ...switch (dataset) {
          'announcements' || 'news' => {
            'feed': () =>
                NotificationService().getFeedItems(forceRefresh: true),
          },
          'holiday' || 'academic-dates' => {
            'holiday': () => HolidayTiming.getTodayStatus(forceRefresh: true),
          },
          'ramadan' => {
            dataset: () => RamadanTiming.getRamadanStatus(forceRefresh: true),
          },
          'map' || 'transport' => {
            dataset: () =>
                FeedService().refreshPublicFeed(datasetUrls[dataset]!),
          },
          'materials' => {
            dataset: () => MaterialsService().loadSources(forceRefresh: true),
          },
          'exammap' => {dataset: _refreshExamOverrides},
          _ => const <String, Future<void> Function()>{},
        },
    };
    await Future.wait(
      owners.entries.map((owner) async {
        try {
          await owner.value();
        } catch (error) {
          unawaited(
            AppLog.write('Cache refresh failed (${owner.key}): $error'),
          );
        }
      }),
    );
  }

  Future<void> _refreshExamOverrides() async {
    final sections = ScheduleService().getStudentSectionsSync() ?? <Section>[];
    final sessionId =
        ExamScheduleService().resolveSemesterSessionId(sections) ??
        AppStorage.instance.getIntSync(StorageKeys.currentSessionSemesterId);
    if (sessionId == null || sessionId <= 0) return;
    await ExamMapService().getOverridesForSemester(
      semesterSessionId: sessionId,
      forceRefresh: true,
    );
  }

  static Future<void> runInParallel<T>(
    List<T> items,
    int limit,
    Future<void> Function(T item) task,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await task(items[next++]);
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < math.min(limit, items.length); i++) worker(),
    ]);
  }
}
