import 'dart:async';
import 'dart:convert';
// ignore: implementation_imports
import 'package:chrome_extension/src/internal_helpers.dart';

import 'package:chrome_extension/context_menus.dart' as cm;
import 'package:chrome_extension/chrome.dart';
import 'package:chrome_extension/tabs.dart';
import 'package:chrome_extension/side_panel.dart';
import 'package:chrome_extension/web_navigation.dart';
import 'package:web/web.dart' show Headers, RequestInit, Response;
import 'package:preconnect/tools/web_extension_api_config.dart';
import 'package:preconnect/tools/web_extension_session_sync.dart';
import 'package:preconnect/tools/pkce.dart';

const String _pendingLoginKey = 'preconnect.pendingLogin';
const String _pendingLogoutKey = 'preconnect.pendingLogout';
const String _loginStartedType = 'preconnect.loginStarted';
const String _loginCompleteType = 'preconnect.loginComplete';
const String _loginFailedType = 'preconnect.loginFailed';
const String _logoutCompleteType = 'preconnect.logoutComplete';
const String _startLoginType = 'preconnect.startLogin';
const String _startLogoutType = 'preconnect.startLogout';
const String _browserShortcutType = 'preconnect.browserShortcut';
const String _pendingShortcutPrefsKey = 'pending_shortcut_action';
const String _appEntryPoint = 'index.html';
const String _openSidePanelCommand = 'open_side_panel';
const String _openCustomScheduleCommand = 'open_custom_schedule';
const String _openProfileCommand = 'open_profile';
const String _openClassesCommand = 'open_classes';
const String _openExamsCommand = 'open_exams';
const String _openFriendsScheduleCommand = 'open_friends_schedule';
const String _openShareScheduleCommand = 'open_share_schedule';
const String _openScanScheduleCommand = 'open_scan_schedule';
const String _openSeatStatusCommand = 'open_seat_status';
const String _menuRootId = 'preconnect.menu.root';
const String _menuSidePanelId = 'preconnect.menu.sidePanel';
const String _menuDashboardId = 'preconnect.menu.dashboard';
const String _menuProfileId = 'preconnect.menu.profile';
const String _menuClassesId = 'preconnect.menu.classes';
const String _menuExamsId = 'preconnect.menu.exams';
const String _menuFriendsId = 'preconnect.menu.friends';
const String _menuShareId = 'preconnect.menu.share';
const String _menuScanId = 'preconnect.menu.scan';
const String _menuSeatStatusId = 'preconnect.menu.seatStatus';
const String _shortcutCustomSchedule = 'quick.customSchedule';
const String _shortcutProfile = 'quick.profile';
const String _shortcutClasses = 'quick.classes';
const String _shortcutExams = 'quick.exams';
const String _shortcutFriends = 'quick.friends';
const String _shortcutShare = 'quick.share';
const String _shortcutScan = 'quick.scan';
const String _shortcutSeatStatus = 'quick.seatStatus';

@JS('fetch')
external JSPromise<Response> _fetch(String input, [RequestInit? init]);

Future<void> main() async {
  await _guarded(_configureBrowserSurfaces);

  chrome.runtime.onStartup.listen((_) {
    unawaited(
      _guarded(() async {
        await _bootstrapSessionSync();
        await _restoreAppTabAfterStartup();
      }),
    );
  });
  chrome.runtime.onInstalled.listen((_) {
    unawaited(
      _guarded(() async {
        await _bootstrapSessionSync();
      }),
    );
  });

  chrome.action.onClicked.listen((tab) {
    if (chrome.sidePanel.isAvailable) return;
    unawaited(_guarded(_openOrFocusAppTab));
  });

  chrome.commands.onCommand.listen((event) {
    unawaited(
      _guarded(() async {
        await _handleCommand(event.command, event.tab);
      }),
    );
  });

  chrome.contextMenus.onClicked.listen((event) {
    unawaited(
      _guarded(() async {
        await _handleContextMenu(event.info, event.tab);
      }),
    );
  });

  chrome.runtime.onMessage.listen((event) {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';
    if (type != _startLoginType) return;
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
    unawaited(_guarded(_startLogin));
  });

  chrome.runtime.onMessage.listen((event) {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';
    if (type != _startLogoutType) return;
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
    unawaited(_guarded(_startLogout));
  });

  chrome.webNavigation.onCommitted.listen((details) {
    unawaited(_guarded(() => _handleNavigation(details)));
  });

  chrome.tabs.onRemoved.listen((event) {
    unawaited(_guarded(() => _handleTabRemoved(event)));
  });

  unawaited(_guarded(_bootstrapSessionSync));
}

Future<void> _guarded(Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {
  }
}

Future<void> _openOrFocusAppTab() async {
  final appUrl = chrome.runtime.getURL(_appEntryPoint);
  final tabs = await chrome.tabs.query(QueryInfo());
  for (final tab in tabs) {
    final tabUrl = tab.url?.trim();
    if (tabUrl != appUrl) continue;
    final tabId = tab.id;
    if (tabId == null) continue;
    await chrome.tabs.update(tabId, UpdateProperties(active: true));
    return;
  }

  await chrome.tabs.create(CreateProperties(url: appUrl, active: true));
}

Future<void> _configureBrowserSurfaces() async {
  if (chrome.sidePanel.isAvailable) {
    await chrome.sidePanel.setOptions(
      PanelOptions(path: _appEntryPoint, enabled: true),
    );
    await chrome.sidePanel.setPanelBehavior(
      PanelBehavior(openPanelOnActionClick: true),
    );
  }

  if (!chrome.contextMenus.isAvailable) return;
  await chrome.contextMenus.removeAll();
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuRootId,
      title: 'PreConnect',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuSidePanelId,
      parentId: _menuRootId,
      title: 'Open side panel',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuDashboardId,
      parentId: _menuRootId,
      title: 'Custom Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuProfileId,
      parentId: _menuRootId,
      title: 'Profile',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuClassesId,
      parentId: _menuRootId,
      title: 'Class Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuExamsId,
      parentId: _menuRootId,
      title: 'Exam Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuFriendsId,
      parentId: _menuRootId,
      title: 'Friend Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuShareId,
      parentId: _menuRootId,
      title: 'Share Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuScanId,
      parentId: _menuRootId,
      title: 'Scan Schedule',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
  chrome.contextMenus.create(
    cm.CreateProperties(
      id: _menuSeatStatusId,
      parentId: _menuRootId,
      title: 'Seat Status',
      contexts: [cm.ContextType.action],
    ),
    null,
  );
}

Future<void> _handleCommand(String command, Tab? tab) async {
  switch (command) {
    case _openSidePanelCommand:
      await _openSidePanel(tab: tab);
      return;
    case _openCustomScheduleCommand:
      await _activateBrowserShortcut(_shortcutCustomSchedule, tab: tab);
      return;
    case _openProfileCommand:
      await _activateBrowserShortcut(_shortcutProfile, tab: tab);
      return;
    case _openClassesCommand:
      await _activateBrowserShortcut(_shortcutClasses, tab: tab);
      return;
    case _openExamsCommand:
      await _activateBrowserShortcut(_shortcutExams, tab: tab);
      return;
    case _openFriendsScheduleCommand:
      await _activateBrowserShortcut(_shortcutFriends, tab: tab);
      return;
    case _openShareScheduleCommand:
      await _activateBrowserShortcut(_shortcutShare, tab: tab);
      return;
    case _openScanScheduleCommand:
      await _activateBrowserShortcut(_shortcutScan, tab: tab);
      return;
    case _openSeatStatusCommand:
      await _activateBrowserShortcut(_shortcutSeatStatus, tab: tab);
      return;
  }
}

Future<void> _handleContextMenu(cm.OnClickData info, Tab? tab) async {
  final menuItemId = '${info.menuItemId}';
  switch (menuItemId) {
    case _menuSidePanelId:
      await _openSidePanel(tab: tab);
      return;
    case _menuDashboardId:
      await _activateBrowserShortcut(_shortcutCustomSchedule, tab: tab);
      return;
    case _menuProfileId:
      await _activateBrowserShortcut(_shortcutProfile, tab: tab);
      return;
    case _menuClassesId:
      await _activateBrowserShortcut(_shortcutClasses, tab: tab);
      return;
    case _menuExamsId:
      await _activateBrowserShortcut(_shortcutExams, tab: tab);
      return;
    case _menuFriendsId:
      await _activateBrowserShortcut(_shortcutFriends, tab: tab);
      return;
    case _menuShareId:
      await _activateBrowserShortcut(_shortcutShare, tab: tab);
      return;
    case _menuScanId:
      await _activateBrowserShortcut(_shortcutScan, tab: tab);
      return;
    case _menuSeatStatusId:
      await _activateBrowserShortcut(_shortcutSeatStatus, tab: tab);
      return;
  }
}

Future<void> _openSidePanel({Tab? tab}) async {
  if (!chrome.sidePanel.isAvailable) {
    await _openOrFocusAppTab();
    return;
  }

  final resolvedTab = tab ?? await _activeTab();
  if (resolvedTab?.windowId != null) {
    await chrome.sidePanel.open(OpenOptions(windowId: resolvedTab!.windowId));
    return;
  }
  if (resolvedTab?.id != null) {
    await chrome.sidePanel.open(OpenOptions(tabId: resolvedTab!.id));
    return;
  }
  final activeWindowId = await _activeWindowId();
  if (activeWindowId != null) {
    await chrome.sidePanel.open(OpenOptions(windowId: activeWindowId));
    return;
  }
  await _openOrFocusAppTab();
}

Future<void> _activateBrowserShortcut(
  String shortcut, {
  Tab? tab,
}) async {
  await _persistPendingShortcutAction(shortcut);
  unawaited(_broadcastRuntimeMessage({
    'type': _browserShortcutType,
    'shortcut': shortcut,
  }));
  await _openSidePanel(tab: tab);
}

Future<void> _persistPendingShortcutAction(String shortcut) async {
  await chrome.storage.local.set({
    _pendingShortcutPrefsKey: shortcut,
  });
}

Future<Tab?> _activeTab() async {
  final tabs = await chrome.tabs.query(
    QueryInfo(active: true, currentWindow: true),
  );
  if (tabs.isNotEmpty) return tabs.first;
  final fallbackTabs = await chrome.tabs.query(QueryInfo(active: true));
  if (fallbackTabs.isNotEmpty) return fallbackTabs.first;
  return null;
}

Future<int?> _activeWindowId() async {
  final tab = await _activeTab();
  if (tab?.windowId != null) return tab!.windowId;
  return null;
}

Future<void> _bootstrapSessionSync() async {
  await _syncLatestSession();
}

Future<void> _syncLatestSession() async {
  await ensureFreshWebExtensionSession();
}

Future<void> _restoreAppTabAfterStartup() async {
  if (chrome.sidePanel.isAvailable) {
    return;
  }
  final hasSession = await _hasStoredAuthSession();
  if (!hasSession) return;
  await _openOrFocusAppTab();
}

Future<bool> _hasStoredAuthSession() async {
  final values = await chrome.storage.local.get([
    'access_token',
    'refresh_token',
  ]);
  final accessToken = '${values['access_token'] ?? ''}'.trim();
  final refreshToken = '${values['refresh_token'] ?? ''}'.trim();
  return accessToken.isNotEmpty && refreshToken.isNotEmpty;
}

class _PendingLogin {
  const _PendingLogin({
    required this.tabId,
    required this.verifier,
    required this.startedAtMillis,
  });

  final int tabId;
  final String verifier;
  final int startedAtMillis;

  Map<String, Object> toJson() => {
    'tabId': tabId,
    'verifier': verifier,
    'startedAtMillis': startedAtMillis,
  };

  static _PendingLogin? fromJson(Object? value) {
    if (value is! Map) return null;
    final tabId = int.tryParse('${value['tabId'] ?? ''}');
    final verifier = '${value['verifier'] ?? ''}';
    final startedAtMillis = int.tryParse('${value['startedAtMillis'] ?? ''}');
    if (tabId == null || verifier.isEmpty || startedAtMillis == null) {
      return null;
    }
    return _PendingLogin(
      tabId: tabId,
      verifier: verifier,
      startedAtMillis: startedAtMillis,
    );
  }
}

Future<void> _startLogin() async {
  if (!chrome.tabs.isAvailable) {
    await _broadcastFailure('Tabs API is not available.');
    return;
  }
  final pending = await _loadPendingLogin();
  if (pending != null) {
    await _broadcastFailure('A login flow is already running.');
    return;
  }

  final verifier = generatePkceVerifier();
  final challenge = codeChallengeS256(verifier);
  final authUrl = WebExtensionApiConfig.authUrlWithPkce(challenge);

  try {
    final tab = await chrome.tabs.create(
      CreateProperties(url: authUrl, active: true),
    );
    if (tab.id == null) {
      await _broadcastFailure('Unable to open the login tab.');
      return;
    }
    await _savePendingLogin(
      _PendingLogin(
        tabId: tab.id!,
        verifier: verifier,
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await chrome.runtime.sendMessage(
      null,
      {'type': _loginStartedType, 'tabId': tab.id},
      null,
    );
  } catch (e) {
    await _broadcastFailure('Unable to start login: $e');
  }
}

Future<void> _startLogout() async {
  if (!chrome.tabs.isAvailable) {
    return;
  }

  final activeTabs = await chrome.tabs.query(
    QueryInfo(active: true, currentWindow: true),
  );
  final appTabId = activeTabs.isNotEmpty ? activeTabs.first.id : null;

  final logoutUrl = Uri.parse(
    'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/logout',
  ).replace(
    queryParameters: {
      'client_id': WebExtensionApiConfig.clientId,
      'post_logout_redirect_uri': WebExtensionApiConfig.redirectUri,
    },
  );

  final tab = await chrome.tabs.create(
    CreateProperties(url: logoutUrl.toString(), active: true),
  );
  final logoutTabId = tab.id;
  if (appTabId == null || logoutTabId == null) {
    return;
  }

  await chrome.storage.session.set({
    _pendingLogoutKey: {
      'appTabId': appTabId,
      'logoutTabId': logoutTabId,
      'startedAtMillis': DateTime.now().millisecondsSinceEpoch,
    },
  });
}

Future<void> _handleNavigation(OnCommittedDetails details) async {
  if (await _handleLogoutNavigation(details)) {
    return;
  }

  final pending = await _loadPendingLogin();
  if (pending == null || pending.tabId != details.tabId) return;
  final uri = Uri.tryParse(details.url);
  if (uri == null) return;
  if (uri.scheme != 'https') return;
  if (uri.host != 'connect.bracu.ac.bd') return;
  if (!uri.path.contains('/student/profile/overview')) return;

  final code = uri.queryParameters['code']?.trim() ?? '';
  if (code.isEmpty) {
    await _failAndClear('Login callback did not include an authorization code.');
    return;
  }

  try {
    await chrome.tabs.remove(details.tabId);
  } catch (_) {}

  try {
    final tokens = await _exchangeCodeForTokens(
      code: code,
      verifier: pending.verifier,
    );
    await chrome.storage.local.set({
      'access_token': tokens.accessToken,
      'refresh_token': tokens.refreshToken,
      'cached_has_auth_session': 'true',
    });
    await _clearPendingLogin();
    if (!chrome.sidePanel.isAvailable) {
      unawaited(_openOrFocusAppTab());
    }
    await chrome.runtime.sendMessage(
      null,
      {
        'type': _loginCompleteType,
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
      },
      null,
    );
  } catch (e) {
    await _failAndClear('Unable to complete login: $e');
  }
}

class _PendingLogout {
  const _PendingLogout({
    required this.appTabId,
    required this.logoutTabId,
    required this.startedAtMillis,
  });

  final int? appTabId;
  final int logoutTabId;
  final int startedAtMillis;

  Map<String, Object?> toJson() => {
    'appTabId': appTabId,
    'logoutTabId': logoutTabId,
    'startedAtMillis': startedAtMillis,
  };

  static _PendingLogout? fromJson(Object? value) {
    if (value is! Map) return null;
    final logoutTabId = int.tryParse('${value['logoutTabId'] ?? ''}');
    final startedAtMillis = int.tryParse('${value['startedAtMillis'] ?? ''}');
    final appTabIdValue = value['appTabId'];
    final appTabId = appTabIdValue == null
        ? null
        : int.tryParse('$appTabIdValue');
    if (logoutTabId == null || startedAtMillis == null) {
      return null;
    }
    return _PendingLogout(
      appTabId: appTabId,
      logoutTabId: logoutTabId,
      startedAtMillis: startedAtMillis,
    );
  }
}

Future<bool> _handleLogoutNavigation(OnCommittedDetails details) async {
  final pending = await _loadPendingLogout();
  if (pending == null || pending.logoutTabId != details.tabId) return false;

  final uri = Uri.tryParse(details.url);
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  if (uri.host != 'connect.bracu.ac.bd') return false;
  if (!uri.path.contains('/student/profile/overview')) return false;

  await _clearPendingLogout();
  try {
    await chrome.tabs.remove(details.tabId);
  } catch (_) {}

  if (pending.appTabId != null) {
    try {
      await chrome.tabs.update(
        pending.appTabId,
        UpdateProperties(active: true),
      );
    } catch (_) {}
  } else {
    await _openOrFocusAppTab();
  }

  unawaited(_broadcastRuntimeMessage({'type': _logoutCompleteType}));
  return true;
}

Future<void> _handleTabRemoved(OnRemovedEvent event) async {
  final pendingLogout = await _loadPendingLogout();
  if (pendingLogout != null && pendingLogout.logoutTabId == event.tabId) {
    await _clearPendingLogout();
    return;
  }

  final pending = await _loadPendingLogin();
  if (pending == null || pending.tabId != event.tabId) return;
  await _failAndClear('Login tab was closed before sign-in completed.');
}

Future<void> _failAndClear(String error) async {
  await _clearPendingLogin();
  await _broadcastFailure(error);
}

Future<void> _broadcastFailure(String error) async {
  unawaited(
    _broadcastRuntimeMessage({'type': _loginFailedType, 'error': error}),
  );
}

Future<void> _broadcastRuntimeMessage(Map<String, Object?> message) async {
  try {
    await chrome.runtime.sendMessage(null, message, null);
  } catch (_) {
  }
}

Future<void> _savePendingLogin(_PendingLogin pending) async {
  await chrome.storage.session.set({_pendingLoginKey: pending.toJson()});
}

Future<_PendingLogin?> _loadPendingLogin() async {
  final values = await chrome.storage.session.get(_pendingLoginKey);
  return _PendingLogin.fromJson(values[_pendingLoginKey]);
}

Future<void> _clearPendingLogin() async {
  await chrome.storage.session.remove(_pendingLoginKey);
}

Future<_PendingLogout?> _loadPendingLogout() async {
  final values = await chrome.storage.session.get(_pendingLogoutKey);
  return _PendingLogout.fromJson(values[_pendingLogoutKey]);
}

Future<void> _clearPendingLogout() async {
  await chrome.storage.session.remove(_pendingLogoutKey);
}

class _TokenResponse {
  const _TokenResponse({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

Future<_TokenResponse> _exchangeCodeForTokens({
  required String code,
  required String verifier,
}) async {
  final body = Uri(
    queryParameters: {
      'grant_type': 'authorization_code',
      'client_id': WebExtensionApiConfig.clientId,
      'code': code,
      'redirect_uri': WebExtensionApiConfig.redirectUri,
      'code_verifier': verifier,
    },
  ).query;
  final response = await _fetch(
    WebExtensionApiConfig.tokenEndpoint,
    RequestInit(
      method: 'POST',
      headers: Headers()..append('Content-Type', 'application/x-www-form-urlencoded'),
      body: body.toJS,
    ),
  ).toDart;
  final status = response.status;
  final text = (await response.text().toDart).toDart;
  if (status != 200) {
    throw Exception(text.isEmpty ? 'Token exchange failed ($status)' : text);
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object from token endpoint');
  }
  final accessToken = '${decoded['access_token'] ?? ''}';
  final refreshToken = '${decoded['refresh_token'] ?? ''}';
  if (accessToken.isEmpty || refreshToken.isEmpty) {
    throw const FormatException('Token response missing access or refresh token');
  }
  return _TokenResponse(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );
}
