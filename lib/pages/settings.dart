import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/device_diagnostics.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/export_sheet.dart';
import 'package:preconnect/tools/quiet_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/runtime_web.dart';

class SettingsPage extends HookWidget {
  const SettingsPage({super.key});

  static const double _sectionGap = 14;

  @override
  Widget build(BuildContext context) {
    final showQuickAccessSection = useSignal(true);
    final showRamadanCard = useSignal(true);
    final showExamCountdownCard = useSignal(true);
    final showTodaySchedule = useSignal(true);
    final showDecorations = useSignal(true);
    final showCampusMapContacts = useSignal(true);
    final showNotificationsIcon = useSignal(true);
    final showFundingSection = useSignal(true);
    final appLockEnabled = useSignal(false);
    final quietModeEnabled = useSignal(false);
    final quietModeNeedsSetup = useSignal(false);
    final quietModeSetupPermission = useSignal<String?>(null);
    final quietModeStatusMessage = useSignal('');

    Future<void> load() async {
      final visibility = await HomeCardPreferences.load();
      final appLock = await AppLockService().isEnabled();
      await QuietModeController.instance.load();
      final quietModeResult = await QuietModeController.instance.refresh();
      showQuickAccessSection.value = visibility.showQuickAccessSection;
      showRamadanCard.value = visibility.showRamadanCard;
      showDecorations.value = visibility.showDecorations;
      showCampusMapContacts.value = visibility.showCampusMapContacts;
      showNotificationsIcon.value = visibility.showNotificationsIcon;
      showExamCountdownCard.value = visibility.showExamCountdownCard;
      showTodaySchedule.value = visibility.showTodaySchedule;
      showFundingSection.value = visibility.showFundingSection;
      appLockEnabled.value = appLock;
      quietModeEnabled.value = QuietModeController.instance.isEnabled;
      quietModeNeedsSetup.value =
          quietModeResult.status == 'permission_required';
      quietModeSetupPermission.value = quietModeResult.permission;
      quietModeStatusMessage.value = quietModeNeedsSetup.value
          ? (quietModeResult.message ?? '')
          : '';
    }

    useEffect(() {
      final observer = _SettingsLifecycleObserver(onResume: load);
      WidgetsBinding.instance.addObserver(observer);
      load();
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, const []);

    Future<void> setVisibility({
      required String label,
      required bool value,
      required void Function() applyLocal,
      required Future<void> Function(bool) persist,
    }) async {
      applyLocal();
      await persist(value);
      RefreshBus.instance.notify(reason: 'home_card_settings_changed');
      if (context.mounted) {
        showAppSnackBar(context, '$label ${value ? 'enabled' : 'disabled'}');
      }
    }

    Future<void> setAppLock(bool value) async {
      if (value) {
        final confirmed = await AppLockService().authenticate();
        if (!confirmed) {
          if (context.mounted) {
            showAppSnackBar(
              context,
              'Verification failed. App lock not enabled',
            );
          }
          return;
        }
      }
      await AppLockService().setEnabled(value);
      appLockEnabled.value = value;
      RefreshBus.instance.notify(reason: 'app_lock_settings_changed');
      if (context.mounted) {
        showAppSnackBar(
          context,
          value ? 'App lock enabled' : 'App lock disabled',
        );
      }
    }

    Future<void> setQuietMode(bool value) async {
      final result = await QuietModeController.instance.setEnabled(
        value,
        promptForPermission: value,
      );
      quietModeEnabled.value = QuietModeController.instance.isEnabled;
      quietModeNeedsSetup.value = result.status == 'permission_required';
      quietModeSetupPermission.value = result.permission;
      quietModeStatusMessage.value = quietModeNeedsSetup.value
          ? (result.message ?? '')
          : '';
      RefreshBus.instance.notify(reason: 'quiet_mode_settings_changed');

      if (context.mounted) {
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

    Future<void> fixQuietModeSetup() async {
      final result = await QuietModeController.instance.requestSetup();
      quietModeEnabled.value = QuietModeController.instance.isEnabled;
      quietModeNeedsSetup.value = result.status == 'permission_required';
      quietModeSetupPermission.value = result.permission;
      quietModeStatusMessage.value = quietModeNeedsSetup.value
          ? (result.message ?? '')
          : '';
      RefreshBus.instance.notify(reason: 'quiet_mode_settings_changed');
    }

    String quietModeSetupMsg() {
      switch (quietModeSetupPermission.value) {
        case 'notification_policy':
          return 'Needs DND access to automate Quiet Mode.';
        case 'exact_alarms':
          return 'Needs device alarm access to keep schedule timing precise.';
        default:
          return quietModeStatusMessage.value.isNotEmpty
              ? quietModeStatusMessage.value
              : 'Quiet Mode needs system access to automate schedules.';
      }
    }

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
        onRefresh: load,
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
                  value: showTodaySchedule.value,
                  onChanged: (val) => setVisibility(
                    label: 'Today\'s Schedule',
                    value: val,
                    applyLocal: () => showTodaySchedule.value = val,
                    persist: HomeCardPreferences.setShowTodaySchedule,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Quick Access',
                  subtitle: 'Show quick shortcuts on home',
                  value: showQuickAccessSection.value,
                  onChanged: (val) => setVisibility(
                    label: 'Quick Access',
                    value: val,
                    applyLocal: () => showQuickAccessSection.value = val,
                    persist: HomeCardPreferences.setShowQuickAccessSection,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Funding Campaign',
                  subtitle: 'Show funding campaign section',
                  value: showFundingSection.value,
                  onChanged: (val) => setVisibility(
                    label: 'Funding Campaign',
                    value: val,
                    applyLocal: () => showFundingSection.value = val,
                    persist: HomeCardPreferences.setShowFundingSection,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Exam Countdown',
                  subtitle: 'Show upcoming exam countdown',
                  value: showExamCountdownCard.value,
                  onChanged: (val) => setVisibility(
                    label: 'Exam Countdown',
                    value: val,
                    applyLocal: () => showExamCountdownCard.value = val,
                    persist: HomeCardPreferences.setShowExamCountdownCard,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Notifications Icon',
                  subtitle: 'Show bell icon on home',
                  value: showNotificationsIcon.value,
                  onChanged: (val) => setVisibility(
                    label: 'Notifications Icon',
                    value: val,
                    applyLocal: () => showNotificationsIcon.value = val,
                    persist: HomeCardPreferences.setShowNotificationsIcon,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Ramadan Times',
                  subtitle: 'Show Sehri and Iftar times',
                  value: showRamadanCard.value,
                  onChanged: (val) => setVisibility(
                    label: 'Ramadan Times',
                    value: val,
                    applyLocal: () => showRamadanCard.value = val,
                    persist: HomeCardPreferences.setShowRamadanCard,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Campus Map & Contacts',
                  subtitle: 'Show contacts card on home',
                  value: showCampusMapContacts.value,
                  onChanged: (val) => setVisibility(
                    label: 'Campus Map & Contacts',
                    value: val,
                    applyLocal: () => showCampusMapContacts.value = val,
                    persist: HomeCardPreferences.setShowCampusMapContacts,
                  ),
                ),
                divider,
                _ToggleRow(
                  title: 'Decorations',
                  subtitle: 'Show UI background decorations',
                  value: showDecorations.value,
                  onChanged: (val) => setVisibility(
                    label: 'Decorations',
                    value: val,
                    applyLocal: () => showDecorations.value = val,
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
                  value: quietModeEnabled.value,
                  onChanged: setQuietMode,
                ),
                if (quietModeNeedsSetup.value) ...[
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
                            quietModeSetupMsg(),
                            style: TextStyle(
                              fontSize: 12,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ),
                        const Gap(10),
                        TextButton(
                          onPressed: fixQuietModeSetup,
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
              value: appLockEnabled.value,
              onChanged: setAppLock,
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

class _SettingsLifecycleObserver extends WidgetsBindingObserver {
  _SettingsLifecycleObserver({required this.onResume});
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
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
