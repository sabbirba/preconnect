import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_models.dart';

class WebLoginSetupPage extends StatefulWidget {
  const WebLoginSetupPage({super.key});

  @override
  State<WebLoginSetupPage> createState() => _WebLoginSetupPageState();
}

class _WebLoginSetupPageState extends State<WebLoginSetupPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );
  final WebLoginBrokerService _broker = WebLoginBrokerService();
  bool? _cameraGranted;
  bool _busy = false;
  String? _status;
  bool _loadingSessions = false;
  List<WebActiveSession> _activeSessions = const <WebActiveSession>[];

  List<WebActiveSession> _dedupeSessions(List<WebActiveSession> sessions) {
    final byKey = <String, WebActiveSession>{};
    for (final session in sessions) {
      if (session.revoked) continue;
      final key = session.webSessionId.trim().isNotEmpty
          ? session.webSessionId.trim()
          : '${_sessionLabel(session)}|${session.userAgent}|${session.studentEmail}';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = session;
        continue;
      }
      final existingRank = existing.revoked ? 0 : 1;
      final incomingRank = session.revoked ? 0 : 1;
      if (incomingRank > existingRank ||
          session.lastSeenAtMillis > existing.lastSeenAtMillis) {
        byKey[key] = session;
      }
    }
    final deduped = byKey.values.toList();
    deduped.sort((a, b) => b.lastSeenAtMillis.compareTo(a.lastSeenAtMillis));
    return deduped;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePermission();
    _loadActiveSessions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _cameraGranted == true &&
        !_busy) {
      _controller.start().catchError((e) {});
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
    }
  }

  Future<void> _ensurePermission() async {
    final granted = await PlatformPermissions.requestScannerCameraPermission();
    if (!mounted) return;
    setState(() => _cameraGranted = granted);
    if (granted) {
      await _controller.start().catchError((e) {});
    }
  }

  Future<void> _refreshAll() async {
    await _ensurePermission();
    await _loadActiveSessions();
  }

  Future<void> _loadActiveSessions() async {
    if (!mounted) return;
    setState(() {
      _loadingSessions = true;
    });
    try {
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Please sign in on this phone first.');
      }
      final sessions = await _broker.listActiveSessions(
        accessToken: accessToken,
      );
      if (!mounted) return;
      setState(() {
        _activeSessions = _dedupeSessions(sessions);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingSessions = false;
        });
      }
    }
  }

  Future<void> _revokeSession(WebActiveSession session) async {
    if (_loadingSessions) return;
    try {
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Please sign in on this phone first.');
      }
      await _broker.revokeSession(
        accessToken: accessToken,
        webSessionId: session.webSessionId,
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Web session logged out');
      await _loadActiveSessions();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _sessionLabel(WebActiveSession session) {
    final ua = session.userAgent.toLowerCase();
    if (ua.contains('safari') && !ua.contains('chrome')) return 'Safari';
    if (ua.contains('chrome')) return 'Chrome';
    if (ua.contains('firefox')) return 'Firefox';
    if (ua.contains('edg')) return 'Edge';
    return 'Browser session';
  }

  Future<void> _approve(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    await _controller.stop();
    try {
      final request = WebLoginRequestPayload.fromQrData(raw);
      if (request.type != 'web_login_request' || request.isExpired) {
        throw Exception('This browser QR is expired.');
      }
      final profile = await ProfileService().getProfile();
      final profileEmail = (profile?['studentEmail'] ?? profile?['email'] ?? '')
          .trim()
          .toLowerCase();
      final qrSessionEmail = request.studentEmail.trim().toLowerCase();
      final approvalEmail = profileEmail.contains('@')
          ? profileEmail
          : (qrSessionEmail.contains('@')
                ? qrSessionEmail
                : 'web@preconnect.app');
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      final refreshToken =
          (await TokenStorage.instance.read(key: 'refresh_token'))?.trim() ??
          '';
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw Exception('Mobile login is required before approving web login.');
      }
      await _broker.approve(
        request: request,
        payload: WebLoginApprovePayload(
          studentEmail: approvalEmail,
          studentId: (profile?['studentId'] ?? '').trim(),
          accessToken: accessToken,
          refreshToken: refreshToken,
          sessionExpiresAtMillis: DateTime.utc(
            2100,
            1,
            1,
          ).millisecondsSinceEpoch,
        ),
      );
      await _loadActiveSessions();
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _loadActiveSessions();
        }
      });
      if (!mounted) return;
      setState(() {
        _status = 'Web login approved for $approvalEmail';
      });
      showAppSnackBar(context, 'Web login approved');
      await _loadActiveSessions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString().replaceFirst('Exception: ', '');
      });
      showAppSnackBar(context, _status ?? 'Unable to approve web login');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_cameraGranted == true) {
          await _controller.start().catchError((e) {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Login to Web',
      subtitle: 'Scan browser QR',
      icon: Icons.qr_code_scanner_rounded,
      body: _cameraGranted == null
          ? buildRefreshLoadingState(
              onRefresh: _refreshAll,
              topSpacing: 180,
            )
          : BracuRefreshList(
              onRefresh: _refreshAll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
          const BracuSectionTitle(title: 'Scan Browser QR'),
          const SizedBox(height: 10),
          BracuCard(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _cameraGranted == true
                    ? MobileScanner(
                        controller: _controller,
                        errorBuilder: (context, error) {
                          final isPermissionError =
                              error.errorCode ==
                              MobileScannerErrorCode.permissionDenied;
                          final message =
                              (error.errorDetails?.message?.trim().isNotEmpty ??
                                  false)
                              ? error.errorDetails!.message!
                              : error.errorCode.message;
                          return Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.white,
                                  size: 34,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () {
                                    if (isPermissionError) {
                                      _ensurePermission();
                                      return;
                                    }
                                    _ensurePermission();
                                  },
                                  child: const Text(
                                    'Retry Camera',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        onDetect: (capture) {
                          if (capture.barcodes.isEmpty) return;
                          final raw =
                              capture.barcodes.first.rawValue?.trim() ?? '';
                          if (raw.isNotEmpty) {
                            _approve(raw);
                          }
                        },
                      )
                    : (_cameraGranted == null
                          ? const Center(child: _WebLoginLoadingState())
                          : Center(
                              child: TextButton(
                                onPressed: _ensurePermission,
                                child: Text(
                                  'Tap to enable camera',
                                  style: TextStyle(
                                    color: BracuPalette.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )),
              ),
            ),
          ),
          const SizedBox(height: 14),
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Active Web Sessions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loadingSessions ? null : _loadActiveSessions,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (_loadingSessions)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: BracuShimmer(
                      child: BracuSkeletonBox(height: 3, radius: 2),
                    ),
                  ),
                if (!_loadingSessions && _activeSessions.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No active browser sessions.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  for (final session in _activeSessions) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: BracuPalette.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  _sessionLabel(session),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: BracuPalette.textPrimary(context),
                                  ),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: session.revoked
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  session.revoked ? 'Logged Out' : 'Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: session.revoked
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: session.revoked
                                ? null
                                : () => _revokeSession(session),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: Row(
              children: [
                Icon(
                  _busy
                      ? Icons.hourglass_top_rounded
                      : Icons.verified_user_outlined,
                  color: BracuPalette.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _status ??
                        (_busy
                            ? 'Approving browser login...'
                            : 'Scan the browser QR and approve login.'),
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => openExternalUrl(
              context,
              'https://web.preconnect.app',
              failureMessage: 'Unable to open web.preconnect.app',
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: BracuPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.open_in_new,
                        color: BracuPalette.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open PreConnect Web',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PreConnect • Prepare. Connect. Succeed.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
            ),
    );
  }
}

class _WebLoginLoadingState extends StatelessWidget {
  const _WebLoginLoadingState();

  @override
  Widget build(BuildContext context) {
    return BracuShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          BracuSkeletonBox(width: 180, height: 16, radius: 7),
          SizedBox(height: 10),
          BracuSkeletonBox(width: 220, height: 12, radius: 6),
          SizedBox(height: 14),
          BracuSkeletonBox(width: 260, height: 180, radius: 18),
        ],
      ),
    );
  }
}
