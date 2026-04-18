import 'package:flutter/material.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/web_login_setup.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const double _sectionGap = 14;

  bool _isLoading = true;
  bool _showQuickAccessSection = true;
  bool _showRamadanCard = true;
  bool _showExamCountdownCard = true;
  bool _showTodaySchedule = true;
  bool _showSponsoredContent = true;
  bool _appLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final visibility = await HomeCardPreferences.load();
    final appLockEnabled = await AppLockService().isEnabled();
    if (!mounted) return;
    setState(() {
      _showQuickAccessSection = visibility.showQuickAccessSection;
      _showRamadanCard = visibility.showRamadanCard;
      _showExamCountdownCard = visibility.showExamCountdownCard;
      _showTodaySchedule = visibility.showTodaySchedule;
      _showSponsoredContent = visibility.showSponsoredContent;
      _appLockEnabled = appLockEnabled;
      _isLoading = false;
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

  Future<void> _setShowSponsoredContent(bool value) async {
    await _setVisibility(
      label: 'Sponsored Content',
      value: value,
      applyLocal: () => _showSponsoredContent = value,
      persist: HomeCardPreferences.setShowSponsoredContent,
    );
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
          if (_isLoading)
            const BracuLoading(itemCount: 5)
          else ...[
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
                    title: Text('Wi-Fi Auto Login Setup'),
                    trailing: Icon(Icons.chevron_right_rounded, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebLoginSetupPage(),
                    ),
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
                    leading: Icon(Icons.language_rounded, size: 20),
                    title: Text('Login to Web'),
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
                    title: 'Sponsored Content',
                    subtitle: 'Show sponsor sections in the app',
                    value: _showSponsoredContent,
                    onChanged: _setShowSponsoredContent,
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
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),
            BracuCard(
              child: _ToggleRow(
                title: 'App Lock',
                subtitle: 'Use system lock for the app',
                value: _appLockEnabled,
                onChanged: _setAppLockEnabled,
              ),
            ),
          ],
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
