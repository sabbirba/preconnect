part of 'package:preconnect/pages/home.dart';

Future<void> syncTodayWidgetInBackground({bool forceRefresh = false}) async {
  try {
    await AppStorage.initialize();
    if (forceRefresh) {
      ApiClient().clearTransientCaches();
    }
    final data = await _HomeDashboardState.preloadData(
      forceRefresh: forceRefresh,
    );
    final state = _HomeDashboardState();
    await state._syncTodayWidget(data);
    if (forceRefresh) {
      await state._saveHomeDashboardSnapshot(data);
    }
    unawaited(NotificationsPage.preloadData(forceRefresh: forceRefresh));
  } catch (_) {}
}

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.onNavigate, required this.onLogout});

  final void Function(HomeTab tab) onNavigate;
  final Future<void> Function() onLogout;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> with RefreshBusState {
  static const _bgTop = Colors.white;
  static const _bgBottom = Colors.white;
  static const _primary = Color(0xFF1E6BE3);

  int _scheduleMinute = DateTime.now().minute;
  Timer? _scheduleTimer;
  late Future<_HomeData> _future;
  _HomeData? _latestData;
  bool _isRefreshing = false;
  bool _refreshInFlight = false;
  bool _isBackgroundLoggingIn = false;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;

  bool _isAutoExtendingSession = false;
  DateTime? _lastAutoAssistantOpenAt;
  DateTime? _lastSilentLoginAt;
  String? _lastObservedApMac;

  static const Duration _silentLoginTimeout = Duration(seconds: 45);
  static const String _homeDashboardSnapshotCacheKey =
      'home_dashboard_snapshot_v1';
  static _HomeData? _cachedData;
  static Future<_HomeData>? _preloadFuture;
  static DateTime? _lastBackgroundRefreshAt;
  static const Duration _minBackgroundRefreshInterval = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();

    final forceRefresh = isRefreshingFrom('auth');
    if (forceRefresh) {
      _cachedData = null;
      _preloadFuture = null;
    }
    _loadHomeDashboardSnapshotSync();
    _future = _latestData != null
        ? Future<_HomeData>.value(_latestData!)
        : _initializeHomeData(forceRefresh: forceRefresh);
    unawaited(_warmAndBind(forceRefresh: forceRefresh));
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen((
        status,
      ) {
        if (!mounted) return;
        unawaited(_consumePostConnectionEvent());
        unawaited(_maybeAutoExtendSession(status));
        final apMac = status.apMac;
        final roamedAp =
            _lastObservedApMac != null &&
            apMac != null &&
            apMac != _lastObservedApMac;
        _lastObservedApMac = apMac;

        final shouldOpenAssistant =
            status.captive ||
            (status.transport == 'wifi' &&
                status.connected &&
                !status.validated) ||
            (roamedAp && (status.captive || !status.validated));
        if (shouldOpenAssistant) {
          unawaited(_maybeAutoOpenWifiAssistant(status));
        }
      });
      unawaited(_consumePostConnectionEvent());
    }

    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (mounted && now.minute != _scheduleMinute) {
        setState(() => _scheduleMinute = now.minute);
      }
    });
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    unbindRefreshBus(_onRefreshSignal);
    _networkStatusSubscription?.cancel().catchError((_) {});

    super.dispose();
  }

  static _HomeData _withCurrentVisibilitySync(_HomeData data) {
    final visibility = HomeCardPreferences.loadSync();
    return data.copyWith(cardVisibility: visibility);
  }

  static _HomeData? _loadHomeDashboardSnapshotSyncHelper() {
    final cached = RepositoryCache.instance.readJsonSync(
      _homeDashboardSnapshotCacheKey,
      (decoded) => decoded is Map
          ? _HomeData.fromCache(Map<String, dynamic>.from(decoded))
          : null,
    );
    if (cached != null) {
      return _withCurrentVisibilitySync(cached);
    }
    try {
      final profile = ProfileService.storedProfileSync();
      final fullName = profile['fullName'];
      final studentId = profile['studentId'];
      if ((fullName != null && fullName.trim().isNotEmpty) ||
          (studentId != null && studentId.trim().isNotEmpty)) {
        final photoUrl = ApiConfig.photoUrl(profile['photoFilePath']);
        final scheduleJson = AppStorage.instance.getStringSync(
          StorageKeys.studentSchedule,
        );
        final sections = section.parseSectionsFromScheduleJson(scheduleJson);
        final entries = _ScheduleEntry.buildEntries(
          sections: sections,
          overrides: const <String, ExamScheduleOverride>{},
          isRamadan: false,
        );
        final fallbackData = _HomeData(
          profile: profile,
          entries: entries,
          photoUrl: photoUrl,
          sections: sections,
          examOverrides: const <String, ExamScheduleOverride>{},
          personalSchedules: const <CustomSchedule>[],
          isRamadan: false,
          ramadan: const RamadanStatus(isRamadan: false),
          holiday: HolidayStatus.empty,
          cardVisibility: HomeCardPreferences.loadSync(),
          scheduleJson: scheduleJson,
          advisingInfo: null,
        );
        return fallbackData;
      }
    } catch (_) {}
    return null;
  }

  void _loadHomeDashboardSnapshotSync() {
    if (_cachedData != null) {
      _latestData = _cachedData;
      return;
    }
    final cached = _loadHomeDashboardSnapshotSyncHelper();
    if (cached != null) {
      _latestData = cached;
      _cachedData = cached;
    }
  }

  Future<void> _loadHomeDashboardSnapshot() async {
    try {
      final raw = await RepositoryCache.instance.readString(
        _homeDashboardSnapshotCacheKey,
      );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = _HomeData.fromCache(Map<String, dynamic>.from(decoded));
      if (cached == null || !mounted) return;
      final merged = await _withCurrentVisibility(cached);
      if (!mounted) return;
      setState(() {
        _latestData = merged;
        _cachedData = merged;
      });
    } catch (_) {}
  }

  Future<void> _backgroundRefresh({bool ignoreMinInterval = false}) async {
    if (_refreshInFlight || _isRefreshing) return;
    final lastRefresh = _lastBackgroundRefreshAt;
    if (!ignoreMinInterval &&
        lastRefresh != null &&
        DateTime.now().difference(lastRefresh) <
            _minBackgroundRefreshInterval) {
      return;
    }
    _refreshInFlight = true;
    _lastBackgroundRefreshAt = DateTime.now();
    try {
      final fresh = await _loadData(forceRefresh: true);
      if (!fresh.hasProfileIdentity && _latestData != null) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _latestData = fresh;
        _cachedData = fresh;
        _future = Future<_HomeData>.value(fresh);
      });
      unawaited(_saveHomeDashboardSnapshot(fresh));
    } catch (_) {
    } finally {
      _refreshInFlight = false;
    }
  }

  static void _warmQuickAccessPages() {
    for (final preload in <Future<void> Function()>[
      ClassSchedulePage.preload,
      ExamSchedule.preload,
      DegreeProgressPage.preload,
      StudentProfile.preload,
      CustomSchedulesPage.preload,
      AlarmPage.preload,
    ]) {
      unawaited(preload());
    }
  }

  Future<void> _warmAndBind({bool forceRefresh = false}) async {
    try {
      if (_latestData != null) {
        _warmQuickAccessPages();
        unawaited(_backgroundRefresh(ignoreMinInterval: forceRefresh));
        return;
      }
      final data = await preloadData(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _latestData = data;
        _future = Future<_HomeData>.value(data);
      });
      _warmQuickAccessPages();
      unawaited(_saveHomeDashboardSnapshot(data));
      if (!forceRefresh) {
        unawaited(_backgroundRefresh());
      }
    } catch (_) {}
  }

  Future<void> _saveHomeDashboardSnapshot(_HomeData data) async {
    if (!data.hasProfileIdentity) return;
    try {
      await RepositoryCache.instance.writeString(
        _homeDashboardSnapshotCacheKey,
        jsonEncode(data.toCacheJson()),
      );
    } catch (_) {}
  }

  Future<_HomeData> _initializeHomeData({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedData != null) {
      return _cachedData!;
    }
    if (!forceRefresh) {
      await _loadHomeDashboardSnapshot();
    }
    if (_cachedData != null) {
      return _cachedData!;
    }
    return _preloadHomeDashboardData(forceRefresh: forceRefresh);
  }

  static Future<_HomeData> preloadData({bool forceRefresh = false}) async {
    return _preloadHomeDashboardData(forceRefresh: forceRefresh);
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('home_card_settings_changed')) {
      unawaited(_reloadCardVisibilityOnly());
      return;
    }
    unawaited(_backgroundRefresh(ignoreMinInterval: true));
  }

  Future<void> _reloadCardVisibilityOnly() async {
    final visibility = await HomeCardPreferences.load();
    if (!mounted) return;
    setState(() {
      if (_latestData != null) {
        _latestData = _latestData!.copyWith(cardVisibility: visibility);
      }
      if (_cachedData != null) {
        _cachedData = _cachedData!.copyWith(cardVisibility: visibility);
      }
    });
  }

  static Future<_HomeData> _withCurrentVisibility(_HomeData data) async {
    return _withCurrentVisibilitySync(data);
  }

  Future<_HomeData> _loadData({bool forceRefresh = false}) async {
    try {
      final profileFuture =
          (forceRefresh
                  ? ProfileService().fetchProfile()
                  : ProfileService().getProfile())
              .catchError((e) => null);

      final customSchedulesFuture =
          (forceRefresh
                  ? CustomSchedulesService().getItems(forceRefresh: true)
                  : CustomSchedulesService().getItems())
              .catchError((e) => const <CustomSchedule>[]);

      final advisingFuture =
          (forceRefresh
                  ? AdvisingService().fetchAdvisingInfo()
                  : AdvisingService().getAdvisingInfo())
              .catchError((e) => null);

      final (cardVisibility, currentSessionSemesterId) = await (
        HomeCardPreferences.load().catchError(
          (_) => HomeCardPreferences.defaults,
        ),
        resolveCurrentSessionSemesterId(
          forceRefresh: forceRefresh,
        ).catchError((_) => null),
      ).wait;

      final needsSchedule =
          cardVisibility.showTodaySchedule ||
          cardVisibility.showExamCountdownCard;
      final needsRamadan =
          cardVisibility.showRamadanCard || cardVisibility.showTodaySchedule;
      final needsHoliday = cardVisibility.showTodaySchedule;

      final scheduleFuture = currentSessionSemesterId == null || !needsSchedule
          ? Future<List<section.Section>>.value(const <section.Section>[])
          : ScheduleService()
                .getUnifiedStudentSchedule(
                  semesterSessionId: currentSessionSemesterId,
                  forceRefresh: forceRefresh,
                )
                .catchError((e) => const <section.Section>[]);

      final ramadanFuture = needsRamadan
          ? RamadanTiming.getRamadanStatus(
              forceRefresh: forceRefresh,
            ).catchError((e) => const RamadanStatus(isRamadan: false))
          : Future<RamadanStatus>.value(const RamadanStatus(isRamadan: false));

      final holidayFuture = needsHoliday
          ? HolidayTiming.getTodayStatus(
              forceRefresh: forceRefresh,
            ).catchError((e) => HolidayStatus.empty)
          : Future<HolidayStatus>.value(HolidayStatus.empty);

      final results = await Future.wait<dynamic>([
        profileFuture,
        customSchedulesFuture,
        advisingFuture,
        scheduleFuture,
        ramadanFuture,
        holidayFuture,
      ]);

      var profile = results[0] as Map<String, String?>?;
      if (profile == null ||
          ((profile['studentId'] ?? '').trim().isEmpty &&
              (profile['fullName'] ?? '').trim().isEmpty)) {
        final storage = AppStorage.instance;
        final fullName = storage.getStringSync(StorageKeys.fullName);
        final studentId = storage.getStringSync(StorageKeys.studentId);
        if ((fullName != null && fullName.trim().isNotEmpty) ||
            (studentId != null && studentId.trim().isNotEmpty)) {
          profile = <String, String?>{
            'fullName': fullName,
            'studentId': studentId,
            'studentEmail': storage.getStringSync(StorageKeys.studentEmail),
            'shortCode': storage.getStringSync(StorageKeys.shortCode),
            'program': storage.getStringSync(StorageKeys.program),
            'departmentName': storage.getStringSync(StorageKeys.departmentName),
            'currentSemester': storage.getStringSync(
              StorageKeys.currentSemester,
            ),
            'currentSessionSemesterId': storage.getStringSync(
              StorageKeys.currentSessionSemesterId,
            ),
            'cgpa': storage.getStringSync(StorageKeys.cgpa),
            'earnedCredit': storage.getStringSync(StorageKeys.earnedCredit),
            'mobileNo': storage.getStringSync(StorageKeys.mobileNo),
            'photoFilePath': storage.getStringSync(StorageKeys.photoFilePath),
          };
        }
      }
      final personalSchedules = results[1] as List<CustomSchedule>;
      final advisingInfo = results[2] as Map<String, String?>?;
      final sections = results[3] as List<section.Section>;
      final ramadan = results[4] as RamadanStatus;
      final isRamadan = ramadan.isRamadan;
      final holidayStatus = results[5] as HolidayStatus;

      final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
      final examOverridesFuture =
          sections.isNotEmpty && cardVisibility.showExamCountdownCard
          ? ExamScheduleService()
                .getOverridesForSections(sections, forceRefresh: forceRefresh)
                .catchError((e) => const <String, ExamScheduleOverride>{})
          : Future.value(const <String, ExamScheduleOverride>{});
      final extraSectionsFuture =
          currentSessionSemesterId == null || !needsSchedule
          ? Future.value(const <section.Section>[])
          : ExtraClassesStore()
                .sectionsFor(currentSessionSemesterId, sections)
                .catchError((_) => const <section.Section>[]);
      final examOverrides = await examOverridesFuture;
      final extraSections = await extraSectionsFuture;
      final entries = _ScheduleEntry.buildEntries(
        sections: [...sections, ...extraSections],
        overrides: examOverrides,
        isRamadan: isRamadan,
      );
      final scheduleJson = jsonEncode(sections.map((s) => s.toJson()).toList());
      final data = _HomeData(
        profile: profile,
        entries: entries,
        photoUrl: photoUrl,
        sections: sections,
        examOverrides: examOverrides,
        personalSchedules: personalSchedules,
        isRamadan: isRamadan,
        ramadan: ramadan,
        holiday: holidayStatus,
        cardVisibility: cardVisibility,
        scheduleJson: scheduleJson,
        advisingInfo: advisingInfo,
        extraSections: extraSections,
      );
      return await _withCurrentVisibility(data).catchError((_) => data);
    } catch (error) {
      final fallbackVisibility = await HomeCardPreferences.load().catchError((
        _,
      ) {
        return HomeCardPreferences.defaults;
      });
      return _HomeData(
        profile: const <String, String?>{},
        entries: const <_ScheduleEntry>[],
        photoUrl: null,
        sections: const <section.Section>[],
        examOverrides: const <String, ExamScheduleOverride>{},
        personalSchedules: const <CustomSchedule>[],
        isRamadan: false,
        ramadan: const RamadanStatus(isRamadan: false),
        holiday: HolidayStatus.empty,
        cardVisibility: fallbackVisibility,
        scheduleJson: null,
        advisingInfo: null,
      );
    }
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    _isRefreshing = true;
    try {
      unawaited(fetchCampusMapData(forceRefresh: true));
      unawaited(fetchTransportScheduleUrl(forceRefresh: true));
      final fresh = await _loadData(forceRefresh: true);
      if (!mounted) return;
      if (!fresh.hasProfileIdentity && _latestData != null) return;
      setState(() {
        _latestData = fresh;
        _cachedData = fresh;
      });
      unawaited(_saveHomeDashboardSnapshot(fresh));
      if (notify) {
        RefreshBus.instance.notify(reason: 'home_dashboard');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _maybeAutoExtendSession(AndroidNetworkStatus status) async {
    if (!mounted || _isAutoExtendingSession) return;
    final enabled = await CaptiveLoginStore.instance.readAutoExtendEnabled();
    if (!enabled) return;

    if (status.transport != 'wifi' || !status.connected) return;
    final currentSsid = (status.ssid ?? '').trim();
    if (currentSsid.isNotEmpty &&
        currentSsid.toLowerCase() !=
            CaptiveLoginStore.defaultCampusSsid.toLowerCase()) {
      return;
    }

    final isCaptiveOrUnvalidated = status.captive || !status.validated;
    if (!isCaptiveOrUnvalidated) {
      final heartbeatOk = await CaptiveWifiHttp.instance
          .sendKeepAliveHeartbeat();
      if (heartbeatOk) return;
      final now = DateTime.now();
      final lastLoginMs = await CaptiveLoginStore.instance.readLastLoginAt();
      final lastLoginAt = lastLoginMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastLoginMs)
          : _lastSilentLoginAt;
      if (lastLoginAt != null &&
          now.difference(lastLoginAt) < const Duration(hours: 12)) {
        return;
      }
    }

    _isAutoExtendingSession = true;
    try {
      await _silentBackgroundLogin(status);
    } catch (_) {
    } finally {
      _isAutoExtendingSession = false;
    }
  }

  Future<String> _resolveCaptiveStudentId() async {
    var id = (await AppStorage.instance.getString(StorageKeys.studentId) ?? '')
        .trim();
    if (id.isNotEmpty) return id;
    try {
      final profile = await ProfileService().getProfile(fromFetch: false);
      id = (profile?['studentId'] ?? '').toString().trim();
    } catch (_) {}
    return id;
  }

  Future<bool> _silentBackgroundLogin(AndroidNetworkStatus status) async {
    if (_isBackgroundLoggingIn) return false;

    final now = DateTime.now();
    if (_lastSilentLoginAt != null &&
        now.difference(_lastSilentLoginAt!) < const Duration(minutes: 1)) {
      return false;
    }

    final creds = await CaptiveLoginStore.instance.read();
    if (creds == null) return false;

    final studentId = await _resolveCaptiveStudentId();
    if (studentId.isEmpty) return false;

    final captiveWifiUri = CaptiveWifiHttp.resolvePortalUri(status);
    if (captiveWifiUri == null) return false;

    _isBackgroundLoggingIn = true;
    _lastSilentLoginAt = now;
    try {
      await CaptiveWifiHttp.acquireWifiBinding();
      final success = await CaptiveWifiHttp.instance
          .loginViaCaptiveApi(
            studentId: studentId,
            password: creds.password,
            captiveWifiUrl: captiveWifiUri,
          )
          .timeout(_silentLoginTimeout, onTimeout: () => false);
      return success;
    } catch (_) {
      return false;
    } finally {
      await CaptiveWifiHttp.releaseWifiBinding();
      _isBackgroundLoggingIn = false;
    }
  }

  Future<void> _maybeAutoOpenWifiAssistant(AndroidNetworkStatus status) async {
    if (!mounted) return;
    if (status.transport != 'wifi') return;
    if (status.validated && !status.captive) return;

    final isOnline = await CaptiveWifiHttp.checkInternetAccess();
    if (isOnline) return;

    final now = DateTime.now();
    if (_lastAutoAssistantOpenAt != null &&
        now.difference(_lastAutoAssistantOpenAt!) <
            const Duration(seconds: 45)) {
      return;
    }
    _lastAutoAssistantOpenAt = now;

    final captiveWifiUri = CaptiveWifiHttp.resolvePortalUri(status);
    if (captiveWifiUri != null &&
        captiveWifiUri != CaptiveWifiHttp.defaultProbeUri) {
      await CaptiveLoginStore.instance.saveLastPortalUrl(
        captiveWifiUri.toString(),
      );
    }

    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted || creds == null) return;

    await _silentBackgroundLogin(status);
  }

  Future<void> _consumePostConnectionEvent() async {
    if (!AndroidNetworkAssist.isSupported || !mounted) return;
    final event = await AndroidNetworkAssist.getAndClearPostConnectionEvent();
    final pending = event['pending'] == true;
    if (!pending) return;
    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted || creds == null) return;

    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (!mounted) return;

    if (status != null) {
      await _silentBackgroundLogin(status);
    }
  }

  _HomeData? _derivedForData;
  String? _derivedForDay;
  _DerivedDashboardData? _derivedCache;

  _DerivedDashboardData _deriveDashboardValues(_HomeData? data) {
    final now = DateTime.now();
    final day = AppTime.formatLongDate(now);
    final cached = _derivedCache;
    if (cached != null &&
        identical(_derivedForData, data) &&
        _derivedForDay == day) {
      return cached;
    }
    final result = _DerivedDashboardData(
      today: _scheduleOn(data, now),
      nextCountdown: _nextDeadlineCountdown(
        data?.sections ?? const <section.Section>[],
        data?.examOverrides ?? const <String, ExamScheduleOverride>{},
        data?.personalSchedules ?? const <CustomSchedule>[],
        data?.advisingInfo,
      ),
    );
    _derivedForData = data;
    _derivedForDay = day;
    _derivedCache = result;
    unawaited(_syncTodayWidget(data));
    return result;
  }

  _DaySchedule _scheduleOn(_HomeData? data, DateTime day) {
    final sections = data?.sections ?? const <section.Section>[];
    final overrides =
        data?.examOverrides ?? const <String, ExamScheduleOverride>{};
    final holiday = data?.holiday ?? HolidayStatus.empty;
    final examWeek = _examWeekStatusOn(sections, overrides, day);
    final exams = _examEntriesOn(sections, overrides, day);
    final noClasses =
        holiday.isHolidayOn(day) || exams.isNotEmpty || examWeek.isActive;
    return _DaySchedule(
      day: _dateOnly(day),
      exams: exams,
      classes: noClasses
          ? const <_ScheduleEntry>[]
          : _classesOn(data?.entries ?? const <_ScheduleEntry>[], day),
      isExamWeek: examWeek.isActive,
      status: AppTodayScheduleStatus.resolve(
        holidayStatus: holiday,
        on: day,
        overrideSubtitle: examWeek.isActive ? examWeek.subtitle : null,
      ),
    );
  }

  List<_ScheduleEntry> _classesOn(List<_ScheduleEntry> entries, DateTime day) {
    final weekday = normalizeWeekday(AppTime.weekdayName(day));
    final date = _dateOnly(day);
    bool startsBy(String? raw) {
      final start = AppTime.parseDate(raw);
      return start == null || !date.isBefore(_dateOnly(start));
    }

    bool endsAfter(String? raw) {
      final end = AppTime.parseDate(raw);
      return end == null || !date.isAfter(_dateOnly(end));
    }

    return entries
        .where(
          (entry) =>
              normalizeWeekday(entry.day) == weekday &&
              startsBy(entry.startDate) &&
              endsAfter(entry.endDate),
        )
        .toList()
      ..sort(
        (a, b) =>
            (AppTime.toMinutes(a.startTime) ?? 0) -
            (AppTime.toMinutes(b.startTime) ?? 0),
      );
  }

  Future<void> _syncTodayWidget(_HomeData? data) async {
    if (!TodayWidget.isSupported) return;
    final now = DateTime.now();
    await TodayWidget.sync([
      for (var offset = 0; offset < TodayWidget.dayCount; offset++)
        _widgetDay(
          _scheduleOn(data, DateTime(now.year, now.month, now.day + offset)),
        ),
    ]);
  }

  TodayWidgetData _widgetDay(_DaySchedule schedule) {
    final status = schedule.status;
    return TodayWidgetData(
      day: TodayWidget.dayKey(schedule.day),
      title: 'Today is ${schedule.weekday}',
      date: schedule.date,
      items: schedule.exams.isNotEmpty
          ? [
              for (final exam in schedule.exams)
                _timedItem(
                  section: exam.sectionName,
                  title: '${exam.courseCode} ${exam.type}',
                  start: exam.startTime,
                  end: exam.endTime,
                  room: exam.room,
                  faculties: exam.faculties,
                ),
            ]
          : schedule.classes.isEmpty
          ? [
              TodayItem(
                badge: status.badge,
                title: status.title,
                subtitle: status.subtitle,
              ),
            ]
          : [
              for (final entry in schedule.classes)
                _timedItem(
                  section: entry.sectionName,
                  title: entry.courseCode,
                  start: entry.startTime,
                  end: entry.endTime,
                  room: entry.roomNumber,
                  faculties: entry.faculties,
                ),
            ],
    );
  }

  TodayItem _timedItem({
    required String section,
    required String title,
    required String? start,
    required String? end,
    required String? room,
    required String? faculties,
  }) => TodayItem(
    badge: formatSectionBadge(section),
    title: title,
    subtitle: formatTimeRange(start, end),
    trailing: (room ?? '').trim(),
    trailingSub: (faculties ?? '').trim(),
    startMinutes: AppTime.toMinutes(start) ?? -1,
    endMinutes: AppTime.toMinutes(end) ?? -1,
  );

  _CountdownCardData? _nextExamCountdown(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final examService = ExamScheduleService();
    final now = DateTime.now();
    final exams = <_CountdownCardData>[];
    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = AppTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (mid != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(mid, now: now)) {
        exams.add(
          _CountdownCardData(
            title: mid.difference(now).inDays <= 3
                ? '${s.courseCode} Midterm'
                : 'Midterm Exam',
            targetDateTime: mid,
            tab: HomeTab.examSchedule,
            subtitle: formatDateTimeLabel(mid),
          ),
        );
      }
      final fin = AppTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (fin != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(fin, now: now)) {
        exams.add(
          _CountdownCardData(
            title: fin.difference(now).inDays <= 7
                ? '${s.courseCode} Final'
                : 'Final Exam',
            targetDateTime: fin,
            tab: HomeTab.examSchedule,
            subtitle: formatDateTimeLabel(fin),
          ),
        );
      }
    }
    final upcoming =
        exams.where((e) => !e.targetDateTime.isBefore(now)).toList()
          ..sort((a, b) => a.targetDateTime.compareTo(b.targetDateTime));
    if (upcoming.isEmpty) return null;
    return upcoming.first;
  }

  _CountdownCardData? _nextMyCountdown(List<CustomSchedule> items) {
    final now = DateTime.now();
    final upcoming =
        items
            .where((item) => !item.isDone && item.startTime.isAfter(now))
            .map(
              (item) => _CountdownCardData(
                title: personalSchedulesCardTitle(item.title),
                targetDateTime: item.startTime,
                tab: HomeTab.personalSchedules,
                subtitle: formatDateTimeLabel(item.startTime),
              ),
            )
            .toList()
          ..sort((a, b) => a.targetDateTime.compareTo(b.targetDateTime));
    if (upcoming.isEmpty) return null;
    return upcoming.first;
  }

  _CountdownCardData? _nextDeadlineCountdown(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
    List<CustomSchedule> personalSchedules,
    Map<String, String?>? advisingInfo,
  ) {
    final nextExam = _nextExamCountdown(sections, overrides);
    final nextMy = _nextMyCountdown(personalSchedules);
    _CountdownCardData? nextAdvising;

    if (advisingInfo != null) {
      final startStr = advisingInfo['advisingStartDate'];
      final endStr = advisingInfo['advisingEndDate'];

      if (startStr != null && endStr != null) {
        final startDate = DateTime.tryParse(startStr);
        final endDate = DateTime.tryParse(endStr);
        if (startDate != null && endDate != null) {
          final now = DateTime.now();
          if (now.isBefore(endDate)) {
            final target = now.isBefore(startDate) ? startDate : endDate;
            nextAdvising = _CountdownCardData(
              title: AdvisingService.title(advisingInfo),
              targetDateTime: target,
              tab: HomeTab.alarms,
              subtitle: formatDateTimeRange(startDate, endDate),
            );
          }
        }
      }
    }

    final candidates = <_CountdownCardData>[];
    if (nextExam != null) candidates.add(nextExam);
    if (nextMy != null) candidates.add(nextMy);
    if (nextAdvising != null) candidates.add(nextAdvising);

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.targetDateTime.compareTo(b.targetDateTime));
    return candidates.first;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  _ExamWeekStatus _examWeekStatusOn(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
    DateTime day,
  ) {
    final examService = ExamScheduleService();
    DateTime? firstMidDate;
    DateTime? lastMidDate;
    DateTime? firstFinalDate;
    DateTime? lastFinalDate;

    void includeExamDate(DateTime value, {required bool isMid}) {
      final date = _dateOnly(value);
      if (isMid) {
        if (firstMidDate == null || date.isBefore(firstMidDate!)) {
          firstMidDate = date;
        }
        if (lastMidDate == null || date.isAfter(lastMidDate!)) {
          lastMidDate = date;
        }
        return;
      }
      if (firstFinalDate == null || date.isBefore(firstFinalDate!)) {
        firstFinalDate = date;
      }
      if (lastFinalDate == null || date.isAfter(lastFinalDate!)) {
        lastFinalDate = date;
      }
    }

    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = AppTime.parseDateTime(resolved.midDate, null);
      if (mid != null) {
        includeExamDate(mid, isMid: true);
      }
      final fin = AppTime.parseDateTime(resolved.finalDate, null);
      if (fin != null) {
        includeExamDate(fin, isMid: false);
      }
    }

    final today = _dateOnly(day);
    final isMidWeek =
        firstMidDate != null &&
        lastMidDate != null &&
        !today.isBefore(firstMidDate!) &&
        !today.isAfter(lastMidDate!);
    final isFinalWeek =
        firstFinalDate != null &&
        lastFinalDate != null &&
        !today.isBefore(firstFinalDate!) &&
        !today.isAfter(lastFinalDate!);

    if (isMidWeek && isFinalWeek) {
      return const _ExamWeekStatus(
        isActive: true,
        subtitle: 'No class today, exam week running.',
      );
    }
    if (isMidWeek) {
      return const _ExamWeekStatus(
        isActive: true,
        subtitle: 'No class today, mid exam week running.',
      );
    }
    if (isFinalWeek) {
      return const _ExamWeekStatus(
        isActive: true,
        subtitle: 'No class today, final exam week running.',
      );
    }
    return const _ExamWeekStatus(isActive: false, subtitle: '');
  }

  List<_TodayExamEntry> _examEntriesOn(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
    DateTime day,
  ) {
    final examService = ExamScheduleService();
    final now = DateTime.now();
    final exams = <_TodayExamEntry>[];
    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = AppTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (mid != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(mid, now: now) &&
          _isSameDate(mid, day)) {
        exams.add(
          _TodayExamEntry(
            dateTime: mid,
            courseCode: s.courseCode,
            type: 'Midterm',
            sectionName: s.sectionName,
            faculties: s.faculties,
            startTime: resolved.midStartTime,
            endTime: resolved.midEndTime,
            room: resolved.midRoomNumber,
          ),
        );
      }
      final fin = AppTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (fin != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(fin, now: now) &&
          _isSameDate(fin, day)) {
        exams.add(
          _TodayExamEntry(
            dateTime: fin,
            courseCode: s.courseCode,
            type: 'Final',
            sectionName: s.sectionName,
            faculties: s.faculties,
            startTime: resolved.finalStartTime,
            endTime: resolved.finalEndTime,
            room: resolved.finalRoomNumber,
          ),
        );
      }
    }
    final seen = <String>{};
    final uniqueExams = exams.where((e) {
      final key =
          '${e.courseCode}|${e.type}|${e.dateTime.millisecondsSinceEpoch}|${e.room ?? ''}';
      return seen.add(key);
    }).toList();
    uniqueExams.sort((a, b) {
      return ExamSorting.compareExamEntries(
        typeA: a.type,
        typeB: b.type,
        dateTimeA: a.dateTime,
        dateTimeB: b.dateTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
    });
    return uniqueExams;
  }

  String? _nextRamadanTarget({String? sehri, String? iftar}) {
    DateTime? nextOccurrence(String? time) {
      final parsed = AppTime.parseTime(time);
      if (parsed == null) return null;
      final now = DateTime.now();
      var target = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.hour,
        parsed.minute,
      );
      if (!target.isAfter(now)) {
        target = target.add(const Duration(days: 1));
      }
      return target;
    }

    final sehriAt = nextOccurrence(sehri);
    final iftarAt = nextOccurrence(iftar);
    if (sehriAt == null && iftarAt == null) return null;
    if (sehriAt == null) return 'Iftar';
    if (iftarAt == null) return 'Sehri';
    return sehriAt.isBefore(iftarAt) ? 'Sehri' : 'Iftar';
  }

  @override
  Widget build(BuildContext context) {
    return _buildHomeDashboardView(context);
  }
}

Future<_HomeData> _preloadHomeDashboardData({bool forceRefresh = false}) async {
  if (!forceRefresh && _HomeDashboardState._cachedData != null) {
    return _HomeDashboardState._withCurrentVisibilitySync(
      _HomeDashboardState._cachedData!,
    );
  }
  if (!forceRefresh) {
    final cached = _HomeDashboardState._loadHomeDashboardSnapshotSyncHelper();
    if (cached != null) {
      _HomeDashboardState._cachedData = cached;
      return cached;
    }
  }
  if (!forceRefresh) {
    final inFlight = _HomeDashboardState._preloadFuture;
    if (inFlight != null) {
      return inFlight;
    }
  }

  final state = _HomeDashboardState();
  final future = state._loadData(forceRefresh: forceRefresh);
  _HomeDashboardState._preloadFuture = future;
  try {
    final data = await future;
    final merged = _HomeDashboardState._withCurrentVisibilitySync(data);
    _HomeDashboardState._cachedData = merged;
    return merged;
  } finally {
    if (identical(_HomeDashboardState._preloadFuture, future)) {
      _HomeDashboardState._preloadFuture = null;
    }
  }
}

class _DerivedDashboardData {
  const _DerivedDashboardData({
    required this.today,
    required this.nextCountdown,
  });

  final _DaySchedule today;
  final _CountdownCardData? nextCountdown;
}

class _DaySchedule {
  const _DaySchedule({
    required this.day,
    required this.exams,
    required this.classes,
    required this.isExamWeek,
    required this.status,
  });

  final DateTime day;
  final List<_TodayExamEntry> exams;
  final List<_ScheduleEntry> classes;
  final bool isExamWeek;
  final AppTodayScheduleStatus status;

  String get weekday => AppTime.weekdayName(day);
  String get date => AppTime.formatLongDate(day);
}

class _ExamWeekStatus {
  const _ExamWeekStatus({required this.isActive, required this.subtitle});

  final bool isActive;
  final String subtitle;
}
