import 'package:flutter/material.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/quiet_mode_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/storage_keys.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  static const double _sectionGap = 14;

  bool _showQuickAccessSection = true;
  bool _showRamadanCard = true;
  bool _showExamCountdownCard = true;
  bool _showTodaySchedule = true;
  bool _appLockEnabled = false;
  bool _showSupport = true;
  bool _quietModeEnabled = false;
  bool _quietModeNeedsSetup = false;
  String? _quietModeSetupPermission;
  String _quietModeStatusMessage = '';
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final visibility = await HomeCardPreferences.load();
    await AdsPreferences.instance.load();
    final appLockEnabled = await AppLockService().isEnabled();
    await QuietModeController.instance.load();
    final quietModeResult = await QuietModeController.instance.refresh();
    if (!mounted) return;
    setState(() {
      _showQuickAccessSection = visibility.showQuickAccessSection;
      _showRamadanCard = visibility.showRamadanCard;
      _showExamCountdownCard = visibility.showExamCountdownCard;
      _showTodaySchedule = visibility.showTodaySchedule;
      _appLockEnabled = appLockEnabled;
      _showSupport = AdsPreferences.instance.isVisible;
      _quietModeEnabled = QuietModeController.instance.isEnabled;
      _quietModeNeedsSetup = quietModeResult.status == 'permission_required';
      _quietModeSetupPermission = quietModeResult.permission;
      _quietModeStatusMessage = _quietModeNeedsSetup
          ? (quietModeResult.message ?? '')
          : '';
    });
  }

  Future<void> _setShowRamadanCard(bool value) async {
    await _setVisibility(
      label: 'Ramadan Times',
      value: value,
      applyLocal: () => _showRamadanCard = value,
      persist: HomeCardPreferences.setShowRamadanCard,
    );
  }

  Future<void> _setShowExamCountdownCard(bool value) async {
    await _setVisibility(
      label: 'Exam Countdown',
      value: value,
      applyLocal: () => _showExamCountdownCard = value,
      persist: HomeCardPreferences.setShowExamCountdownCard,
    );
  }

  Future<void> _setShowQuickAccessSection(bool value) async {
    await _setVisibility(
      label: 'Quick Access',
      value: value,
      applyLocal: () => _showQuickAccessSection = value,
      persist: HomeCardPreferences.setShowQuickAccessSection,
    );
  }

  Future<void> _setShowTodaySchedule(bool value) async {
    await _setVisibility(
      label: 'Today\'s Schedule',
      value: value,
      applyLocal: () => _showTodaySchedule = value,
      persist: HomeCardPreferences.setShowTodaySchedule,
    );
  }

  Future<void> _setShowSupport(bool value) async {
    setState(() {
      _showSupport = value;
    });
    await AdsPreferences.instance.setHidden(!value);
    RefreshBus.instance.notify(reason: 'ads_settings_changed');
    if (!mounted) return;
    showAppSnackBar(context, value ? 'Support shown' : 'Support hidden');
  }

  Future<void> _setVisibility({
    required String label,
    required bool value,
    required void Function() applyLocal,
    required Future<void> Function(bool) persist,
  }) async {
    setState(() {
      applyLocal();
    });
    await persist(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
    if (!mounted) return;
    showAppSnackBar(context, '$label ${value ? 'enabled' : 'disabled'}');
  }

  Future<void> _setAppLockEnabled(bool value) async {
    if (value) {
      final confirmed = await AppLockService().authenticate(
        reason: 'Confirm to enable app lock',
      );
      if (!confirmed) {
        if (!mounted) return;
        showAppSnackBar(context, 'Verification failed. App lock not enabled');
        return;
      }
    }
    await AppLockService().setEnabled(value);
    if (!mounted) return;
    setState(() {
      _appLockEnabled = value;
    });
    RefreshBus.instance.notify(reason: 'app_lock_settings_changed');
    showAppSnackBar(context, value ? 'App lock enabled' : 'App lock disabled');
  }

  Future<void> _setQuietModeEnabled(bool value) async {
    final result = await QuietModeController.instance.setEnabled(
      value,
      promptForPermission: value,
    );
    if (!mounted) return;
    setState(() {
      _quietModeEnabled = QuietModeController.instance.isEnabled;
      _quietModeNeedsSetup = result.status == 'permission_required';
      _quietModeSetupPermission = result.permission;
      _quietModeStatusMessage = _quietModeNeedsSetup
          ? (result.message ?? '')
          : '';
    });
    RefreshBus.instance.notify(reason: 'quiet_mode_settings_changed');

    if (result.status == 'permission_required') {
      return;
    }

    if (result.message != null && result.message!.trim().isNotEmpty) {
      showAppSnackBar(context, result.message!);
      return;
    }

    if (value) {
      showAppSnackBar(context, 'Quiet Mode synced with your schedules.');
    } else {
      showAppSnackBar(context, 'Quiet Mode disabled.');
    }
  }

  Future<void> _fixQuietModeSetup() async {
    final result = await QuietModeController.instance.requestSetup();
    if (!mounted) return;
    setState(() {
      _quietModeEnabled = QuietModeController.instance.isEnabled;
      _quietModeNeedsSetup = result.status == 'permission_required';
      _quietModeSetupPermission = result.permission;
      _quietModeStatusMessage = _quietModeNeedsSetup
          ? (result.message ?? '')
          : '';
    });
    RefreshBus.instance.notify(reason: 'quiet_mode_settings_changed');
  }

  Future<void> _clearCacheKeepingLoginData() async {
    if (_isClearingCache) return;
    setState(() {
      _isClearingCache = true;
    });
    try {
      final keepKeys = <String>{
        PreconnectStorageKeys.accessToken,
        PreconnectStorageKeys.refreshToken,
        PreconnectStorageKeys.cachedHasAuthSession,
        StorageKeys.currentSessionSemesterId,
        CustomSchedulesService.cacheKey,
      };
      await AppPreferencesStore().clearAllExcept(keepKeys);
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
        });
      }
    }

    RefreshBus.instance.notify(reason: 'cache_cleared');
    if (!mounted) return;
    showAppSnackBar(context, 'Cached data cleared');
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Settings',
      subtitle: 'Customize',
      icon: Icons.settings_outlined,
      actions: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.of(context),
          builder: (context, mode, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return IconButton(
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              onPressed: () => ThemeController.setTheme(
                context,
                isDark ? ThemeMode.light : ThemeMode.dark,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                color: BracuPalette.primary,
              ),
            );
          },
        ),
      ],
      body: BracuRefreshList(
        onRefresh: _load,
        showScrollTopButton: false,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CaptiveWifiPage()),
                );
              },
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: BracuPalette.textSecondary(
                      context,
                    ).withValues(alpha: 0.18),
                  ),
                ),
                child: const ListTile(
                  leading: Icon(Icons.wifi_rounded, size: 20),
                  title: Text('Wi-Fi Setup'),
                  trailing: Icon(Icons.chevron_right_rounded, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(height: _sectionGap),
          BracuCard(
            child: Column(
              children: [
                _ToggleRow(
                  title: 'Exam Countdown',
                  subtitle: 'Show upcoming exam countdown',
                  value: _showExamCountdownCard,
                  onChanged: _setShowExamCountdownCard,
                ),
                Divider(
                  height: 12,
                  thickness: 1,
                  color: BracuPalette.textSecondary(context).withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.12,
                  ),
                ),
                _ToggleRow(
                  title: 'Ramadan Times',
                  subtitle: 'Show Sehri and Iftar times',
                  value: _showRamadanCard,
                  onChanged: _setShowRamadanCard,
                ),
                Divider(
                  height: 12,
                  thickness: 1,
                  color: BracuPalette.textSecondary(context).withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.12,
                  ),
                ),
                _ToggleRow(
                  title: 'Today\'s Schedule',
                  subtitle: 'Show today\'s class schedule',
                  value: _showTodaySchedule,
                  onChanged: _setShowTodaySchedule,
                ),
                Divider(
                  height: 12,
                  thickness: 1,
                  color: BracuPalette.textSecondary(context).withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.12,
                  ),
                ),
                _ToggleRow(
                  title: 'Quick Access',
                  subtitle: 'Show quick shortcuts on home',
                  value: _showQuickAccessSection,
                  onChanged: _setShowQuickAccessSection,
                ),
                Divider(
                  height: 12,
                  thickness: 1,
                  color: BracuPalette.textSecondary(context).withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.12,
                  ),
                ),
                _ToggleRow(
                  title: 'Show Support',
                  subtitle: 'Show support content and ads',
                  value: _showSupport,
                  onChanged: _setShowSupport,
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          BracuCard(
            child: Column(
              children: [
                _ToggleRow(
                  title: 'Quiet Mode',
                  subtitle: 'Auto DND for your schedules',
                  value: _quietModeEnabled,
                  onChanged: _setQuietModeEnabled,
                ),
                if (_quietModeNeedsSetup) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BracuPalette.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: BracuPalette.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _quietModeSetupMessage(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _fixQuietModeSetup,
                          child: const Text('Fix'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          BracuCard(
            child: _ToggleRow(
              title: 'App Lock',
              subtitle: 'System lock security for the app',
              value: _appLockEnabled,
              onChanged: _setAppLockEnabled,
            ),
          ),
          const SizedBox(height: _sectionGap),
          BracuActionButton(
            onPressed: _isClearingCache ? null : _clearCacheKeepingLoginData,
            outlined: true,
            isLoading: _isClearingCache,
            icon: Icons.delete_outline_rounded,
            label: 'Clear Cache',
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          const SizedBox(height: _sectionGap),
        ],
      ),
    );
  }

  String _quietModeSetupMessage(BuildContext context) {
    switch (_quietModeSetupPermission) {
      case 'notification_policy':
        return 'Needs DND access to automate Quiet Mode.';
      case 'exact_alarms':
        return 'Needs device alarm access to keep schedule timing precise.';
      default:
        return _quietModeStatusMessage.isNotEmpty
            ? _quietModeStatusMessage
            : 'Quiet Mode needs system access to automate schedules.';
    }
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: BracuPalette.primary,
        ),
      ],
    );
  }
}
