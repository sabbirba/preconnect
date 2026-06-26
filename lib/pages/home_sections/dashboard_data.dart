part of 'package:preconnect/pages/home.dart';

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.onNavigate, required this.onLogout});

  final void Function(HomeTab tab) onNavigate;
  final Future<void> Function() onLogout;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> with RefreshBusState {
  static const _bgTop = Color(0xFFEAF4FF);
  static const _bgBottom = Color(0xFFF3FFF4);
  static const _primary = Color(0xFF1E6BE3);
  static const _accent = Color(0xFF22B573);

  late Future<_HomeData> _future;
  _HomeData? _latestData;
  bool _isRefreshing = false;
  bool _refreshInFlight = false;
  CaptiveWifiStatus? _captiveStatus;
  bool _isCheckingCaptive = false;
  bool _isBackgroundLoggingIn = false;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  bool _autoOpenedWifiAssistant = false;
  bool _isOpeningWifiAssistant = false;
  bool _isAutoExtendingSession = false;
  bool _isConnectingWifi = false;
  DateTime? _lastAutoAssistantOpenAt;
  DateTime? _lastSilentLoginAt;
  Timer? _captiveAutoTimer;
  Timer? _todayScheduleAutoRefreshTimer;
  Future<CampusMapData?>? _campusMapFuture;
  Future<String?>? _transportScheduleUrlFuture;
  bool _quickAccessExpanded = false;

  static const Duration _captiveAutoPollInterval = Duration(seconds: 30);
  static const Duration _todayScheduleAutoRefreshInterval = Duration(
    minutes: 1,
  );
  static const Duration _autoAssistantCooldown = Duration(seconds: 45);
  static const Duration _silentLoginCooldown = Duration(seconds: 90);
  static const Duration _silentLoginTimeout = Duration(seconds: 45);
  static const String _homeDashboardSnapshotCacheKey =
      'home_dashboard_snapshot_v1';
  static _HomeData? _cachedData;
  static Future<_HomeData>? _preloadFuture;
  void _toggleQuickAccess() {
    setState(() {
      _quickAccessExpanded = !_quickAccessExpanded;
    });
  }

  @override
  void initState() {
    super.initState();

    final forceRefresh = isRefreshingFrom('auth');
    if (forceRefresh) {
      _cachedData = null;
      _preloadFuture = null;
    } else {
      _loadHomeDashboardSnapshotSync();
    }
    _future = _initializeHomeData(forceRefresh: forceRefresh);
    unawaited(_warmAndBind(forceRefresh: forceRefresh));
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen(
        _applyAndroidNetworkStatus,
      );
      unawaited(_consumePostConnectionEvent());
      _captiveAutoTimer = Timer.periodic(_captiveAutoPollInterval, (_) {
        if (!mounted) return;
        unawaited(_refreshCaptiveStatus());
      });
    }
    unawaited(_refreshCaptiveStatus());
    _todayScheduleAutoRefreshTimer = Timer.periodic(
      _todayScheduleAutoRefreshInterval,
      (_) {
        if (!mounted) return;
        unawaited(_handleRefresh(notify: false));
      },
    );
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    _networkStatusSubscription?.cancel();
    _captiveAutoTimer?.cancel();
    _todayScheduleAutoRefreshTimer?.cancel();
    super.dispose();
  }

  static _HomeData _withCurrentVisibilitySync(_HomeData data) {
    final visibility = HomeCardPreferences.loadSync();
    return data.copyWith(cardVisibility: visibility);
  }

  static _HomeData? _loadHomeDashboardSnapshotSyncHelper() {
    try {
      final raw = AppStorage.instance.getStringSync(
        _homeDashboardSnapshotCacheKey,
      );
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cached = _HomeData.fromCache(Map<String, dynamic>.from(decoded));
      if (cached == null) return null;
      return _withCurrentVisibilitySync(cached);
    } catch (_) {
      return null;
    }
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

  Future<void> _backgroundRefresh() async {
    if (_refreshInFlight || _isRefreshing) return;
    _refreshInFlight = true;
    try {
      final fresh = await _loadData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _latestData = fresh;
        _cachedData = fresh;
        _future = Future<_HomeData>.value(fresh);
      });
      unawaited(_saveHomeDashboardSnapshot(fresh));
      unawaited(_refreshCaptiveStatus());
    } catch (_) {
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _warmAndBind({bool forceRefresh = false}) async {
    try {
      final data = await preloadData(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _latestData = data;
        _future = Future<_HomeData>.value(data);
      });
      if (!forceRefresh) {
        unawaited(_backgroundRefresh());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _saveHomeDashboardSnapshot(_HomeData data) async {
    if (!data.hasRequiredProfileFields) return;
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
    if (isRefreshingFrom('home_dashboard')) {
      return;
    }
    if (isRefreshingFrom('home_card_settings_changed')) {
      unawaited(_reloadCardVisibilityOnly());
      unawaited(_refreshCaptiveStatus());
      return;
    }
    if (isRefreshingFrom('cache_cleared')) {
      unawaited(_handleRefresh(notify: false));
      return;
    }
    unawaited(_handleRefresh(notify: false));
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
              .catchError((e) {
                return null;
              });

      final customSchedulesFuture =
          (forceRefresh
                  ? CustomSchedulesService().getItems(forceRefresh: true)
                  : CustomSchedulesService().getItems())
              .catchError((e) {
                return const <CustomSchedule>[];
              });

      final advisingFuture =
          (forceRefresh
                  ? AdvisingService().fetchAdvisingInfo()
                  : AdvisingService().getAdvisingInfo())
              .catchError((e) {
                return null;
              });

      final prerequisiteResults = await Future.wait<dynamic>([
        HomeCardPreferences.load(),
        resolveCurrentSessionSemesterId(),
        profileFuture,
        customSchedulesFuture,
        advisingFuture,
      ]);

      final cardVisibility = prerequisiteResults[0] as HomeCardVisibility;
      final currentSessionSemesterId = prerequisiteResults[1] as int?;
      var profile = prerequisiteResults[2] as Map<String, String?>?;
      final personalSchedules = prerequisiteResults[3] as List<CustomSchedule>;
      final advisingInfo = prerequisiteResults[4] as Map<String, String?>?;

      final needsSchedule =
          cardVisibility.showTodaySchedule ||
          cardVisibility.showExamCountdownCard;
      final needsRamadan =
          cardVisibility.showRamadanCard || cardVisibility.showTodaySchedule;
      final needsHoliday = cardVisibility.showTodaySchedule;

      final scheduleFuture = currentSessionSemesterId == null || !needsSchedule
          ? Future<String?>.value(null)
          : (forceRefresh
                    ? ScheduleService().fetchStudentScheduleForSemester(
                        semesterSessionId: currentSessionSemesterId,
                      )
                    : ScheduleService().getStudentScheduleForSemester(
                        semesterSessionId: currentSessionSemesterId,
                      ))
                .catchError((e) {
                  return null;
                });

      final ramadanFuture = needsRamadan
          ? RamadanTiming.getRamadanStatus(
              forceRefresh: forceRefresh,
            ).catchError((e) {
              return const RamadanStatus(isRamadan: false);
            })
          : Future<RamadanStatus>.value(const RamadanStatus(isRamadan: false));

      final holidayFuture = needsHoliday
          ? HolidayTiming.getTodayStatus(forceRefresh: forceRefresh).catchError(
              (e) {
                return HolidayStatus.empty;
              },
            )
          : Future<HolidayStatus>.value(HolidayStatus.empty);

      final secondaryResults = await Future.wait<dynamic>([
        scheduleFuture,
        ramadanFuture,
        holidayFuture,
      ]);

      var scheduleJson = secondaryResults[0] as String?;
      final ramadan = secondaryResults[1] as RamadanStatus;
      final isRamadan = ramadan.isRamadan;
      final holidayStatus = secondaryResults[2] as HolidayStatus;

      if (!forceRefresh &&
          (profile == null || (needsSchedule && scheduleJson == null))) {
        final fallbackResults = await Future.wait<dynamic>([
          profile == null
              ? ProfileService().fetchProfile()
              : Future.value(profile),
          scheduleJson == null &&
                  needsSchedule &&
                  currentSessionSemesterId != null
              ? ScheduleService().fetchStudentScheduleForSemester(
                  semesterSessionId: currentSessionSemesterId,
                )
              : Future.value(scheduleJson),
        ]);
        profile = fallbackResults[0] as Map<String, String?>?;
        scheduleJson = fallbackResults[1] as String?;
      }

      final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
      final List<section.Section> sections = [];
      Map<String, ExamScheduleOverride> examOverrides =
          const <String, ExamScheduleOverride>{};

      Future<Map<String, ExamScheduleOverride>>? examOverridesFuture;

      if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
        final decoded = ScheduleService().parseStudentSections(
          scheduleJson,
          semesterSessionId: currentSessionSemesterId,
        );
        sections.addAll(decoded);
        if (cardVisibility.showExamCountdownCard && sections.isNotEmpty) {
          examOverridesFuture = ExamScheduleService()
              .getOverridesForSections(sections, forceRefresh: forceRefresh)
              .catchError((e) {
                return const <String, ExamScheduleOverride>{};
              });
        }
      }

      if (sections.isEmpty) {
        try {
          final cachedSections = await JsonSnapshotStore.readSections();
          if (cachedSections != null && cachedSections.isNotEmpty) {
            sections.addAll(cachedSections);
            examOverridesFuture = ExamScheduleService()
                .getOverridesForSections(sections, forceRefresh: forceRefresh)
                .catchError((e) {
                  return const <String, ExamScheduleOverride>{};
                });
          }
        } catch (_) {}
      }

      if (examOverridesFuture != null) {
        examOverrides = await examOverridesFuture;
      }
      final List<_ScheduleEntry> entries = [];
      for (final section in sections) {
        if (CourseSectionExamFilter.isFinishedAfterFinalExam(
          section: section,
          overrides: examOverrides,
        )) {
          continue;
        }
        for (final s in section.sectionSchedule.classSchedules) {
          final adjusted = RamadanTiming.adjustRange(
            s.startTime,
            s.endTime,
            isRamadan: isRamadan,
          );
          entries.add(
            _ScheduleEntry(
              day: s.day,
              startTime: adjusted.startTime,
              endTime: adjusted.endTime,
              courseCode: section.courseCode,
              sectionName: section.sectionName,
              roomNumber: section.roomNumber,
              faculties: section.faculties,
            ),
          );
        }
      }
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
      );
      return _withCurrentVisibility(data).catchError((_) => data);
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
      _campusMapFuture = fetchCampusMapData(forceRefresh: true);
      _transportScheduleUrlFuture = fetchTransportScheduleUrl(
        forceRefresh: true,
      );
      final fresh = await _loadData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _latestData = fresh;
      });
      unawaited(_saveHomeDashboardSnapshot(fresh));
      unawaited(_refreshCaptiveStatus());
      if (notify) {
        RefreshBus.instance.notify(reason: 'home_dashboard');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _refreshCaptiveStatus() async {
    if (_isCheckingCaptive) return;
    _isCheckingCaptive = true;
    try {
      if (AndroidNetworkAssist.isSupported) {
        await _consumePostConnectionEvent();
        final status = await AndroidNetworkAssist.getNetworkStatus();
        if (status != null) {
          _applyAndroidNetworkStatus(status);
          return;
        }
      }
      const next = CaptiveWifiStatus(
        state: CaptiveWifiState.unknown,
        httpStatusCode: null,
      );
      if (!mounted ||
          (_captiveStatus?.state == next.state &&
              _captiveStatus?.httpStatusCode == next.httpStatusCode)) {
        return;
      }
      setState(() {
        _captiveStatus = next;
      });
    } finally {
      _isCheckingCaptive = false;
    }
  }

  void _applyAndroidNetworkStatus(AndroidNetworkStatus status) {
    if (!mounted) return;
    final mapped = CaptiveWifiStatus(
      state: status.captive
          ? CaptiveWifiState.captive
          : status.validated
          ? CaptiveWifiState.validated
          : status.connected
          ? CaptiveWifiState.unknown
          : CaptiveWifiState.offline,
      httpStatusCode: null,
    );
    if (_captiveStatus?.state == mapped.state &&
        _captiveStatus?.httpStatusCode == mapped.httpStatusCode) {
      return;
    }
    setState(() {
      _captiveStatus = mapped;
    });
    final shouldOpenAssistant =
        status.captive ||
        (status.transport == 'wifi' && status.connected && !status.validated);
    if (shouldOpenAssistant) {
      unawaited(_maybeAutoOpenWifiAssistant(status));
    } else {
      _autoOpenedWifiAssistant = false;
    }
    unawaited(_maybeAutoExtendSession(status));
  }

  Future<void> _maybeAutoExtendSession(AndroidNetworkStatus status) async {
    if (!mounted || _isAutoExtendingSession) return;
    final enabled = await CaptiveLoginStore.instance.readAutoExtendEnabled();
    if (!enabled) return;

    if (status.transport != 'wifi' || !status.connected) return;
    final currentSsid = (status.ssid ?? '').trim();
    if (currentSsid.isEmpty) return;
    final savedSsid = await CaptiveLoginStore.instance.readSsid();
    if (savedSsid.isEmpty) return;
    final isCampusSsid = currentSsid.toLowerCase() == savedSsid.toLowerCase();
    if (!isCampusSsid) return;

    final now = DateTime.now();
    if (_lastSilentLoginAt != null &&
        now.difference(_lastSilentLoginAt!) < const Duration(hours: 12)) {
      return;
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
        now.difference(_lastSilentLoginAt!) < _silentLoginCooldown) {
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
      await AndroidNetworkAssist.bindToWifiNetwork();
      final success = await CaptiveWifiHttp.instance
          .loginViaCaptiveApi(
            studentId: studentId,
            password: creds.password,
            captiveWifiUrl: captiveWifiUri,
            ssid: status.ssid ?? '',
          )
          .timeout(_silentLoginTimeout, onTimeout: () => false);
      if (success && mounted) {
        unawaited(_refreshCaptiveStatus());
      }
      return success;
    } catch (_) {
      return false;
    } finally {
      await AndroidNetworkAssist.unbindFromWifiNetwork();
      _isBackgroundLoggingIn = false;
    }
  }

  Future<void> _maybeAutoOpenWifiAssistant(AndroidNetworkStatus status) async {
    if (_isOpeningWifiAssistant || !mounted) return;
    if (status.transport != 'wifi') return;
    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted || creds == null) return;
    final currentSsid = (status.ssid ?? '').trim();
    if (currentSsid.isEmpty) return;

    final now = DateTime.now();
    if (_lastAutoAssistantOpenAt != null &&
        now.difference(_lastAutoAssistantOpenAt!) < _autoAssistantCooldown) {
      return;
    }
    _lastAutoAssistantOpenAt = now;

    final silentSuccess = await _silentBackgroundLogin(status);
    if (silentSuccess || !mounted) {
      _autoOpenedWifiAssistant = false;
      return;
    }

    if (_autoOpenedWifiAssistant) return;
    _autoOpenedWifiAssistant = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openWifiLoginAssistant();
    });
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
      final silentSuccess = await _silentBackgroundLogin(status);
      if (silentSuccess || !mounted) return;
    }

    _autoOpenedWifiAssistant = true;
    _lastAutoAssistantOpenAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openWifiLoginAssistant();
    });
  }

  Future<void> _openWifiLoginAssistant() async {
    if (_isOpeningWifiAssistant || !mounted) return;
    _isOpeningWifiAssistant = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              const CaptiveWifiPage(autoOpenCaptiveWifiOnStart: true),
        ),
      );
    } finally {
      _isOpeningWifiAssistant = false;
    }
  }

  Future<void> _runBackgroundWifiConnect() async {
    if (_isConnectingWifi || !mounted) return;

    final creds = await CaptiveLoginStore.instance.read();
    if (creds == null || creds.password.isEmpty) {
      await _openWifiLoginAssistant();
      return;
    }

    final studentId = await _resolveCaptiveStudentId();
    if (studentId.isEmpty) {
      await _openWifiLoginAssistant();
      return;
    }

    setState(() {
      _isConnectingWifi = true;
    });

    try {
      final status = await AndroidNetworkAssist.getNetworkStatus();
      if (status == null) {
        if (mounted) {
          showAppSnackBar(context, 'No Wi-Fi connection');
        }
        return;
      }

      final captiveWifiUri = CaptiveWifiHttp.resolvePortalUri(status);
      if (captiveWifiUri == null) {
        if (mounted) {
          showAppSnackBar(context, 'Portal not found');
        }
        return;
      }

      final savedSsid = await CaptiveLoginStore.instance.readSsid();
      final ssid = (status.ssid ?? savedSsid).trim();
      await AndroidNetworkAssist.bindToWifiNetwork();
      final success = await CaptiveWifiHttp.instance
          .loginViaCaptiveApi(
            studentId: studentId,
            password: creds.password,
            captiveWifiUrl: captiveWifiUri,
            ssid: ssid,
          )
          .timeout(const Duration(seconds: 45), onTimeout: () => false);

      if (mounted) {
        if (success) {
          showAppSnackBar(context, 'Connected!');
          unawaited(_refreshCaptiveStatus());
        } else {
          showAppSnackBar(context, 'Login failed');
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Login error');
      }
    } finally {
      await AndroidNetworkAssist.unbindFromWifiNetwork();
      if (mounted) {
        setState(() {
          _isConnectingWifi = false;
        });
      }
    }
  }

  String _todayName() {
    switch (DateTime.now().weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

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
      final mid = BracuTime.parseDateTime(
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
          ),
        );
      }
      final fin = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (fin != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(fin, now: now)) {
        exams.add(
          _CountdownCardData(
            title: fin.difference(now).inDays <= 3
                ? '${s.courseCode} Final'
                : 'Final',
            targetDateTime: fin,
            tab: HomeTab.examSchedule,
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
      final phase = advisingInfo['advisingPhase'] ?? '';
      final semester = advisingInfo['semesterSession'] ?? '';

      if (startStr != null && endStr != null) {
        final startDate = DateTime.tryParse(startStr);
        final endDate = DateTime.tryParse(endStr);
        if (startDate != null && endDate != null) {
          final now = DateTime.now();
          if (now.isBefore(endDate)) {
            final target = now.isBefore(startDate) ? startDate : endDate;
            final phaseLabel = phase.isEmpty
                ? 'Advising'
                : phase
                      .split('_')
                      .map(
                        (w) => w.isEmpty
                            ? ''
                            : w[0].toUpperCase() + w.substring(1).toLowerCase(),
                      )
                      .join(' ');
            final title = semester.isEmpty
                ? phaseLabel
                : '$phaseLabel - $semester';
            nextAdvising = _CountdownCardData(
              title: title,
              targetDateTime: target,
              tab: HomeTab.alarms,
              subtitle: formatDateTimeRange(
                startDate,
                endDate,
                includeYear: false,
              ),
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

  _ExamWeekStatus _todayExamWeekStatus(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
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
      final mid = BracuTime.parseDateTime(resolved.midDate, null);
      if (mid != null) {
        includeExamDate(mid, isMid: true);
      }
      final fin = BracuTime.parseDateTime(resolved.finalDate, null);
      if (fin != null) {
        includeExamDate(fin, isMid: false);
      }
    }

    final today = _dateOnly(DateTime.now());
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

  List<_TodayExamEntry> _todayExamEntries(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final examService = ExamScheduleService();
    final now = DateTime.now();
    final exams = <_TodayExamEntry>[];
    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = BracuTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (mid != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(mid, now: now) &&
          _isSameDate(mid, now)) {
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
      final fin = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (fin != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(fin, now: now) &&
          _isSameDate(fin, now)) {
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
    exams.sort((a, b) {
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
    return exams;
  }

  int _timeToMinutes(String time) {
    return BracuTime.toMinutes(time) ?? 0;
  }

  String? _nextRamadanTarget({String? sehri, String? iftar}) {
    DateTime? nextOccurrence(String? time) {
      final parsed = BracuTime.parseTime(time);
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

  Future<void> _openCampusMapBottomSheet() async {
    _campusMapFuture ??= fetchCampusMapData();
    _transportScheduleUrlFuture ??= fetchTransportScheduleUrl();
    if (!mounted) return;
    await showCampusMapBottomSheet(
      context,
      campusMapFuture: _campusMapFuture!,
      transportScheduleUrlFuture: _transportScheduleUrlFuture!,
      showContacts: true,
      showCallAction: true,
      collapsedVisibleCount: 5,
    );
  }

  Future<void> _openCampusMapSheet() {
    return _openCampusMapBottomSheet();
  }

  @override
  Widget build(BuildContext context) {
    return _buildHomeDashboardView(context);
  }
}

Future<void> preloadHomeDashboardData({bool forceRefresh = false}) async {
  await _preloadHomeDashboardData(forceRefresh: forceRefresh);
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

class _ExamWeekStatus {
  const _ExamWeekStatus({required this.isActive, required this.subtitle});

  final bool isActive;
  final String subtitle;
}
