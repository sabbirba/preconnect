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
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/reconnect_backoff.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/storage_keys.dart';

class DatasetSync {
  DatasetSync._();
  static final DatasetSync instance = DatasetSync._();

  static const String manifestUrl =
      '${ApiConfig.realtimeApiBase}/sync/manifest';
  static const String streamUrl = '${ApiConfig.realtimeApiBase}/sync/stream';
  static const String datasetUpdatedType = 'dataset_updated';
  static const int parallelDownloads = 4;
  static const String _versionsKey = 'dataset_versions_v1';
  static const Duration _streamSilence = Duration(seconds: 20);

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
    'materials': ApiConfig.materialsUrl,
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

  Future<void>? _manifestCheck;
  Future<void> _versionQueue = Future<void>.value();
  int _liveGeneration = 0;
  StreamSubscription<String>? _liveLines;
  Completer<void>? _liveFinished;

  Future<void> checkManifest() {
    return _manifestCheck ??= _checkManifest().whenComplete(
      () => _manifestCheck = null,
    );
  }

  Future<void> _checkManifest() async {
    final payload = await ApiClient().tryPublicJson(
      manifestUrl,
      cacheDuration: Duration.zero,
    );
    if (payload is Map) await applyVersions(versionsFrom(payload));
  }

  static Map<String, String> versionsFrom(Map<dynamic, dynamic> payload) {
    final datasets = payload['datasets'];
    if (datasets is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in datasets.entries)
        if (entry.value case {
          'version': final String version,
        } when version.isNotEmpty)
          '${entry.key}': version,
    };
  }

  static List<String> changedDatasets(
    Map<String, String> remote,
    Map<String, String> known,
  ) => <String>[
    for (final entry in remote.entries)
      if (datasetUrls.containsKey(entry.key) && known[entry.key] != entry.value)
        entry.key,
  ];

  Future<void> applyVersions(Map<String, String> remote) {
    final queued = _versionQueue.then((_) => _applyVersions(remote));
    _versionQueue = queued.catchError((Object _) {});
    return queued;
  }

  Future<void> _applyVersions(Map<String, String> remote) async {
    final known = await _knownVersions();
    final changed = changedDatasets(remote, known);
    if (changed.isEmpty) return;
    final refreshed = await refresh(changed, expected: remote);
    if (refreshed.isEmpty) return;
    await _saveVersions(<String, String>{
      ...known,
      for (final dataset in refreshed) dataset: ?remote[dataset],
    });
  }

  Future<Set<String>> refresh(
    Iterable<String> datasets, {
    Map<String, String> expected = const <String, String>{},
  }) async {
    final pending = datasets.where(datasetUrls.containsKey).toSet().toList();
    final fresh = <String>{};
    await runInParallel(pending, parallelDownloads, (dataset) async {
      if (await _downloadMatches(dataset, expected[dataset])) {
        fresh.add(dataset);
      }
    });
    await _refreshOwners(fresh);
    for (final reason in fresh.map(_reasonFor).toSet()) {
      RefreshBus.instance.notify(reason: reason);
    }
    return fresh;
  }

  static String compactEtag(String? etag) =>
      (etag ?? '').replaceFirst(RegExp(r'^W/'), '').replaceAll('"', '').trim();

  static bool isFreshResponse(
    Map<String, String> headers,
    String? expectedVersion,
  ) {
    final version = compactEtag(headers['etag']);
    if (version.isEmpty) return false;
    return expectedVersion == null || version == expectedVersion;
  }

  Future<bool> _downloadMatches(String dataset, String? expectedVersion) async {
    try {
      final response = await ApiClient().publicGet(
        datasetUrls[dataset]!,
        cacheDuration: Duration.zero,
      );
      final fresh = isFreshResponse(response.headers, expectedVersion);
      if (!fresh) {
        unawaited(AppLog.write('Dataset not fresh yet ($dataset)'));
      }
      return fresh;
    } catch (error) {
      unawaited(AppLog.write('Dataset refresh failed ($dataset): $error'));
      return false;
    }
  }

  static String _reasonFor(String dataset) =>
      _refreshReasons[dataset] ?? 'dataset_$dataset';

  Future<void> _refreshOwners(Set<String> datasets) async {
    final owners = <String, Future<void> Function()>{};
    for (final dataset in datasets) {
      switch (dataset) {
        case 'announcements' || 'news':
          owners['feed'] = () =>
              NotificationService().getFeedItems(forceRefresh: true);
        case 'holiday' || 'academic-dates':
          owners['holiday'] = () =>
              HolidayTiming.getTodayStatus(forceRefresh: true);
        case 'ramadan':
          owners[dataset] = () =>
              RamadanTiming.getRamadanStatus(forceRefresh: true);
        case 'map' || 'transport':
          owners[dataset] = () =>
              FeedService().refreshPublicFeed(datasetUrls[dataset]!);
        case 'materials':
          owners[dataset] = () =>
              MaterialsService().loadSources(forceRefresh: true);
        case 'exammap':
          owners[dataset] = _refreshExamOverrides;
      }
    }
    await Future.wait(
      owners.entries.map((owner) async {
        try {
          await owner.value();
        } catch (error) {
          unawaited(
            AppLog.write('Dataset cache refresh failed (${owner.key}): $error'),
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

  Future<void> applyPush(Map<String, dynamic> data) async {
    final type = _pushType(data);
    if (type.isEmpty) return;
    try {
      if (type == datasetUpdatedType) {
        final versions = pushVersions(data);
        if (versions.isNotEmpty) {
          await applyVersions(versions);
          return;
        }
        await refresh(
          '${data['datasets'] ?? ''}'
              .split(',')
              .map((dataset) => dataset.trim())
              .where((dataset) => dataset.isNotEmpty),
        );
        return;
      }
      await _applyLegacyPush(type);
    } catch (error) {
      unawaited(AppLog.write('Background sync error ($type): $error'));
    }
  }

  static Map<String, String> pushVersions(Map<String, dynamic> data) {
    try {
      final decoded = jsonDecode('${data['versions'] ?? ''}');
      if (decoded is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value case final String version when version.isNotEmpty)
            '${entry.key}': version,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  static String _pushType(Map<String, dynamic> data) =>
      (data['type'] ??
              data['sync_type'] ??
              data['event'] ??
              data['category'] ??
              data['module'] ??
              data['source'] ??
              data['topic'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();

  Future<void> _applyLegacyPush(String type) async {
    if (type.contains('exam')) {
      await refresh(const <String>['exammap']);
    } else if (type.contains('material')) {
      await refresh(const <String>['materials']);
    } else if (type.contains('notice') ||
        type.contains('announcement') ||
        type.contains('news') ||
        type.contains('notification')) {
      await refresh(const <String>['announcements', 'news']);
      await NotificationService().fetchRecentNotifications();
      RefreshBus.instance.notify(reason: 'notices');
    } else if (type.contains('holiday')) {
      await refresh(const <String>['holiday', 'academic-dates']);
    } else if (type.contains('prerequisite')) {
      await refresh(const <String>['course-prerequisites']);
    } else if (type.contains('bus')) {
      RefreshBus.instance.notify(reason: 'bus');
    } else if (type.contains('seat')) {
      RefreshBus.instance.notify(reason: 'seat_status');
    } else if (type.contains('wifi')) {
      RefreshBus.instance.notify(reason: 'wifi');
    } else if (type.contains('printer')) {
      RefreshBus.instance.notify(reason: 'printer');
    } else if (type.contains('general')) {
      RefreshBus.instance.notify(reason: 'general');
    } else if (type.contains('all') || type == 'sync') {
      await RepositoryCache.instance.remove(StorageKeys.examMapIndex);
      await refresh(datasetUrls.keys);
      RefreshBus.instance.notify(reason: 'global_sync');
    }
  }

  Future<Map<String, String>> _knownVersions() async {
    final raw = await AppStorage.instance.getString(_versionsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveVersions(Map<String, String> versions) {
    return AppStorage.instance.setString(_versionsKey, jsonEncode(versions));
  }

  void startLive() {
    if (kIsWeb) return;
    stopLive();
    unawaited(_runLive(_liveGeneration));
  }

  void stopLive() {
    _liveGeneration++;
    unawaited(_liveLines?.cancel());
    _liveLines = null;
    final finished = _liveFinished;
    if (finished != null && !finished.isCompleted) finished.complete();
    _liveFinished = null;
  }

  Future<void> _runLive(int generation) async {
    final backoff = ReconnectBackoff(
      min: const Duration(seconds: 1),
      max: const Duration(seconds: 30),
    );
    while (generation == _liveGeneration) {
      try {
        final request = http.Request('GET', Uri.parse(streamUrl))
          ..headers['accept'] = 'text/event-stream'
          ..headers['cache-control'] = 'no-cache';
        final response = await HttpUtils.client.send(request);
        if (generation != _liveGeneration || response.statusCode != 200) {
          await response.stream.listen(null).cancel();
        } else {
          backoff.reset();
          await _consumeLive(response.stream, generation);
        }
      } catch (error) {
        unawaited(AppLog.write('Dataset stream error: $error'));
      }
      if (generation != _liveGeneration) return;
      await Future<void>.delayed(backoff.next());
    }
  }

  Future<void> _consumeLive(Stream<List<int>> body, int generation) {
    final finished = _liveFinished = Completer<void>();
    _liveLines = body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_streamSilence, onTimeout: (sink) => sink.close())
        .listen(
          (line) {
            if (generation != _liveGeneration || !line.startsWith('data:')) {
              return;
            }
            final versions = parseStreamVersions(line.substring(5).trim());
            if (versions.isNotEmpty) unawaited(applyVersions(versions));
          },
          onError: (Object _) {
            if (!finished.isCompleted) finished.complete();
          },
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
          cancelOnError: true,
        );
    return finished.future;
  }

  static Map<String, String> parseStreamVersions(String data) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map ? versionsFrom(decoded) : const <String, String>{};
    } catch (_) {
      return const <String, String>{};
    }
  }
}
