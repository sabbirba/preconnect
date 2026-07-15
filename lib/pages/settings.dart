import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/device_diagnostics.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/export_sheet.dart';
import 'package:preconnect/tools/quiet_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

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
  bool _showDecorations = true;
  bool _showCampusMapContacts = true;
  bool _showNotificationsIcon = true;
  bool _showFundingSection = true;
  bool _appLockEnabled = false;
  bool _quietModeEnabled = false;
  bool _quietModeNeedsSetup = false;
  String? _quietModeSetupPermission;
  String _quietModeStatusMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final visibility = await HomeCardPreferences.load();
    final appLock = await AppLockService().isEnabled();
    await QuietModeController.instance.load();
    final quietModeResult = await QuietModeController.instance.refresh();

    if (mounted) {
      setState(() {
        _showQuickAccessSection = visibility.showQuickAccessSection;
        _showRamadanCard = visibility.showRamadanCard;
        _showDecorations = visibility.showDecorations;
        _showCampusMapContacts = visibility.showCampusMapContacts;
        _showNotificationsIcon = visibility.showNotificationsIcon;
        _showExamCountdownCard = visibility.showExamCountdownCard;
        _showTodaySchedule = visibility.showTodaySchedule;
        _showFundingSection = visibility.showFundingSection;
        _appLockEnabled = appLock;
        _quietModeEnabled = QuietModeController.instance.isEnabled;
        _quietModeNeedsSetup = quietModeResult.status == 'permission_required';
        _quietModeSetupPermission = quietModeResult.permission;
        _quietModeStatusMessage = _quietModeNeedsSetup
            ? (quietModeResult.message ?? '')
            : '';
      });
    }
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
    if (mounted) {
      showAppSnackBar(context, '$label ${value ? 'enabled' : 'disabled'}');
    }
  }

  Future<void> _setAppLock(bool value) async {
    if (value) {
      final confirmed = await AppLockService().authenticate();
      if (!confirmed) {
        if (mounted) {
          showAppSnackBar(context, 'Verification failed. App lock not enabled');
        }
        return;
      }
    }
    await AppLockService().setEnabled(value);
    setState(() {
      _appLockEnabled = value;
    });
    RefreshBus.instance.notify(reason: 'app_lock_settings_changed');
    if (mounted) {
      showAppSnackBar(
        context,
        value ? 'App lock enabled' : 'App lock disabled',
      );
    }
  }

  Future<void> _setQuietMode(bool value) async {
    final result = await QuietModeController.instance.setEnabled(
      value,
      promptForPermission: value,
    );
    setState(() {
      _quietModeEnabled = QuietModeController.instance.isEnabled;
      _quietModeNeedsSetup = result.status == 'permission_required';
      _quietModeSetupPermission = result.permission;
      _quietModeStatusMessage = _quietModeNeedsSetup
          ? (result.message ?? '')
          : '';
    });
    RefreshBus.instance.notify(reason: 'quiet_mode_settings_changed');

    if (mounted) {
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
  }

  Future<void> _fixQuietModeSetup() async {
    final result = await QuietModeController.instance.requestSetup();
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

  String _quietModeSetupMsg() {
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

  @override
  Widget build(BuildContext context) {
    Divider divider = Divider(
      height: 12,
      thickness: 1,
      color: BracuPalette.textSecondary(context).withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.12,
      ),
    );

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
        onRefresh: _loadSettings,
        children: [
          BracuActionBannerCard(
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi Setup',
            subtitle: 'Connect to campus captive network',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CaptiveWifiPage()),
              );
            },
          ),
          const Gap(_sectionGap),
          BracuCard(
            child: Column(
              children: [
                _ToggleRow(
                  title: 'Today\'s Schedule',
                  subtitle: 'Show today\'s class schedule',
                  value: _showTodaySchedule,
                  onChanged: (val) => _setVisibility(
                    label: 'Today\'s Schedule',
                    value: val,
                    applyLocal: () => _showTodaySchedule = val,
                    persist: HomeCardPreferences.setShowTodaySchedule,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Quick Access',
                  subtitle: 'Show quick shortcuts on home',
                  value: _showQuickAccessSection,
                  onChanged: (val) => _setVisibility(
                    label: 'Quick Access',
                    value: val,
                    applyLocal: () => _showQuickAccessSection = val,
                    persist: HomeCardPreferences.setShowQuickAccessSection,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Funding Campaign',
                  subtitle: 'Show funding campaign section',
                  value: _showFundingSection,
                  onChanged: (val) => _setVisibility(
                    label: 'Funding Campaign',
                    value: val,
                    applyLocal: () => _showFundingSection = val,
                    persist: HomeCardPreferences.setShowFundingSection,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Exam Countdown',
                  subtitle: 'Show upcoming exam countdown',
                  value: _showExamCountdownCard,
                  onChanged: (val) => _setVisibility(
                    label: 'Exam Countdown',
                    value: val,
                    applyLocal: () => _showExamCountdownCard = val,
                    persist: HomeCardPreferences.setShowExamCountdownCard,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Notifications Icon',
                  subtitle: 'Show bell icon on home',
                  value: _showNotificationsIcon,
                  onChanged: (val) => _setVisibility(
                    label: 'Notifications Icon',
                    value: val,
                    applyLocal: () => _showNotificationsIcon = val,
                    persist: HomeCardPreferences.setShowNotificationsIcon,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Ramadan Times',
                  subtitle: 'Show Sehri and Iftar times',
                  value: _showRamadanCard,
                  onChanged: (val) => _setVisibility(
                    label: 'Ramadan Times',
                    value: val,
                    applyLocal: () => _showRamadanCard = val,
                    persist: HomeCardPreferences.setShowRamadanCard,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Campus Map & Contacts',
                  subtitle: 'Show contacts card on home',
                  value: _showCampusMapContacts,
                  onChanged: (val) => _setVisibility(
                    label: 'Campus Map & Contacts',
                    value: val,
                    applyLocal: () => _showCampusMapContacts = val,
                    persist: HomeCardPreferences.setShowCampusMapContacts,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Decorations',
                  subtitle: 'Show UI background decorations',
                  value: _showDecorations,
                  onChanged: (val) => _setVisibility(
                    label: 'Decorations',
                    value: val,
                    applyLocal: () => _showDecorations = val,
                    persist: HomeCardPreferences.setShowDecorations,
                  ),
                ),
              ],
            ),
          ),
          const Gap(_sectionGap),
          BracuCard(
            child: Column(
              children: [
                _ToggleRow(
                  title: 'Quiet Mode',
                  subtitle: 'Auto DND for your schedules',
                  value: _quietModeEnabled,
                  onChanged: _setQuietMode,
                ),
                if (_quietModeNeedsSetup) ...[
                  const Gap(12),
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
                            _quietModeSetupMsg(),
                            style: TextStyle(
                              fontSize: 12,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ),
                        const Gap(10),
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
          const Gap(_sectionGap),
          BracuCard(
            child: _ToggleRow(
              title: 'App Lock',
              subtitle: 'System lock security for the app',
              value: _appLockEnabled,
              onChanged: _setAppLock,
            ),
          ),
          if (!kIsWeb || isChromeRuntimeAvailable()) ...[
            const Gap(_sectionGap),
            BracuActionBannerCard(
              icon: Icons.qr_code_rounded,
              title: 'Sync Session with Web',
              subtitle: 'Access your session on the web',
              showTrailingIcon: true,
              onTap: () => ExportSessionBottomSheet.show(context),
            ),
          ],
          if (!kIsWeb) ...[
            const Gap(_sectionGap),
            const DeviceDiagnosticsButton(),
          ],
          const Gap(_sectionGap),
        ],
      ),
    );
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
              const Gap(2),
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
        const Gap(12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: BracuPalette.primary,
        ),
      ],
    );
  }
}
