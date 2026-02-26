import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_lock_service.dart';
import 'package:preconnect/tools/home_card_preferences.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final Uri _seatStatusWebUri = Uri.parse(
    'https://seatstatus.preconnect.app/',
  );
  static final Uri _seatStatusDeviceCompleteUri = Uri.parse(
    'https://seatstatus.preconnect.app/auth/device/complete',
  );

  bool _isLoading = true;
  bool _showQuickAccessSection = true;
  bool _showRamadanCard = true;
  bool _showExamCountdownCard = true;
  bool _showExamCountdownDaysOnly = false;
  bool _showTodaySchedule = true;
  bool _showStudentContactCards = true;
  bool _appLockEnabled = false;
  bool _isSubmittingSeatStatusLogin = false;
  bool _isSeatStatusWebConnected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final visibility = await HomeCardPreferences.load();
    final appLockEnabled = await AppLockService().isEnabled();
    final seatStatusWebConnected =
        (await TokenStorage.instance.read(key: 'seat_status_web_connected')) ==
        '1';
    if (!mounted) return;
    setState(() {
      _showQuickAccessSection = visibility.showQuickAccessSection;
      _showRamadanCard = visibility.showRamadanCard;
      _showExamCountdownCard = visibility.showExamCountdownCard;
      _showExamCountdownDaysOnly = visibility.showExamCountdownDaysOnly;
      _showTodaySchedule = visibility.showTodaySchedule;
      _showStudentContactCards = visibility.showStudentContactCards;
      _appLockEnabled = appLockEnabled;
      _isSeatStatusWebConnected = seatStatusWebConnected;
      _isLoading = false;
    });
  }

  Future<void> _setShowRamadanCard(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showRamadanCard = value,
      persist: HomeCardPreferences.setShowRamadanCard,
    );
  }

  Future<void> _setShowExamCountdownCard(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showExamCountdownCard = value,
      persist: HomeCardPreferences.setShowExamCountdownCard,
    );
  }

  Future<void> _setShowQuickAccessSection(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showQuickAccessSection = value,
      persist: HomeCardPreferences.setShowQuickAccessSection,
    );
  }

  Future<void> _setShowExamCountdownDaysOnly(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showExamCountdownDaysOnly = value,
      persist: HomeCardPreferences.setShowExamCountdownDaysOnly,
    );
  }

  Future<void> _setShowTodaySchedule(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showTodaySchedule = value,
      persist: HomeCardPreferences.setShowTodaySchedule,
    );
  }

  Future<void> _setShowStudentContactCards(bool value) async {
    await _setVisibility(
      value: value,
      applyLocal: () => _showStudentContactCards = value,
      persist: HomeCardPreferences.setShowStudentContactCards,
    );
  }

  Future<void> _setVisibility({
    required bool value,
    required void Function() applyLocal,
    required Future<void> Function(bool) persist,
  }) async {
    setState(() {
      applyLocal();
    });
    await persist(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
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

  Future<void> _openSeatStatusPairingPage() async {
    final opened = await launchUrl(
      _seatStatusWebUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!opened) {
      showAppSnackBar(context, 'Could not open Health page');
    }
  }

  Future<void> _submitSeatStatusDeviceCode(String code) async {
    if (_isSubmittingSeatStatusLogin) return;
    setState(() {
      _isSubmittingSeatStatusLogin = true;
    });
    try {
      final storage = TokenStorage.instance;
      final accessToken = (await storage.read(key: 'access_token'))?.trim();
      final refreshToken = (await storage.read(key: 'refresh_token'))?.trim();
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Login tokens not found. Sign in again first.',
        );
        return;
      }

      final response = await http.post(
        _seatStatusDeviceCompleteUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'accessToken': accessToken,
          'refreshToken': refreshToken,
        }),
      );

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        FocusScope.of(context).unfocus();
        await TokenStorage.instance.write(
          key: 'seat_status_web_connected',
          value: '1',
        );
        if (!mounted) return;
        setState(() {
          _isSeatStatusWebConnected = true;
        });
        showAppSnackBar(context, 'Added');
        return;
      }

      String message =
          'Failed to complete browser login (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } catch (_) {}
      showAppSnackBar(context, message);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Network error while sending browser login');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingSeatStatusLogin = false;
        });
      }
    }
  }

  Future<void> _connectSeatStatusFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final code = (data?.text ?? '').trim().toUpperCase();
    if (code.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(context, 'Copy pair code first from web');
      return;
    }
    await _submitSeatStatusDeviceCode(code);
  }

  Future<void> _resetSeatStatusWebConnection() async {
    if (_isSubmittingSeatStatusLogin) return;
    setState(() {
      _isSubmittingSeatStatusLogin = true;
    });
    try {
      await TokenStorage.instance.write(
        key: 'seat_status_web_connected',
        value: null,
      );

      // Best effort: logout browser session on worker side if possible.
      try {
        await http.post(
          Uri.parse('https://seatstatus.preconnect.app/auth/logout'),
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isSeatStatusWebConnected = false;
      });
      if (!mounted) return;
      showAppSnackBar(context, 'Reset complete');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingSeatStatusLogin = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Settings',
      subtitle: 'Customize',
      icon: Icons.settings_outlined,
      body: BracuRefreshList(
        onRefresh: _load,
        children: [
          if (_isLoading)
            const BracuLoading(label: 'Loading settings...')
          else ...[
            const BracuSectionTitle(title: 'Visibility'),
            const SizedBox(height: 10),
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
                    title: 'Exam Days Only',
                    subtitle: 'Show only days in countdown',
                    value: _showExamCountdownDaysOnly,
                    onChanged: _showExamCountdownCard
                        ? _setShowExamCountdownDaysOnly
                        : null,
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
                    title: 'Ramadan & Prayer Times',
                    subtitle: 'Show Ramadan and prayer times',
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
                    subtitle: 'Show today heading and class list',
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
                    title: 'Student Info',
                    subtitle: 'Show student info and phone number',
                    value: _showStudentContactCards,
                    onChanged: _setShowStudentContactCards,
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
                    subtitle: 'Show quick shortcuts section',
                    value: _showQuickAccessSection,
                    onChanged: _setShowQuickAccessSection,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const BracuSectionTitle(title: 'Security'),
            const SizedBox(height: 10),
            BracuCard(
              child: _ToggleRow(
                title: 'App Lock',
                subtitle: 'Use system lock to lock the app',
                value: _appLockEnabled,
                onChanged: _setAppLockEnabled,
              ),
            ),
            const SizedBox(height: 14),
            const BracuSectionTitle(title: 'Health'),
            const SizedBox(height: 10),
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _openSeatStatusPairingPage,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          child: const Text('Open'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmittingSeatStatusLogin
                              ? null
                              : (_isSeatStatusWebConnected
                                    ? _resetSeatStatusWebConnection
                                    : _connectSeatStatusFromClipboard),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          child: Text(
                            _isSubmittingSeatStatusLogin
                                ? '...'
                                : (_isSeatStatusWebConnected
                                      ? 'Reset'
                                      : 'Connect'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
