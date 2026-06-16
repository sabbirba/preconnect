import 'dart:async';
import 'dart:convert';
import 'package:chrome_extension/src/internal_helpers.dart';

import 'package:chrome_extension/cookies.dart' as ck;
import 'package:chrome_extension/context_menus.dart' as cm;
import 'package:chrome_extension/action.dart' as action;
import 'package:chrome_extension/chrome.dart';
import 'package:chrome_extension/alarms.dart' as alarms;
import 'package:chrome_extension/notifications.dart' as notifications;
import 'package:chrome_extension/scripting.dart' as scripting;
import 'package:chrome_extension/tabs.dart';
import 'package:chrome_extension/side_panel.dart';
import 'package:chrome_extension/web_navigation.dart';
import 'package:chrome_extension/gcm.dart';
import 'package:web/web.dart' show Headers, RequestInit, Response;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/bracu_logout.dart';
import 'package:preconnect/tools/extension_config.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/session_sync.dart';
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
const String _appEntryPoint = 'index.html';
const String _openSidePanelCommand =
    PreConnectBrowserActionIds.openSidePanelCommand;
const String _openCustomScheduleCommand =
    PreConnectBrowserActionIds.openCustomScheduleCommand;
const String _openProfileCommand =
    PreConnectBrowserActionIds.openProfileCommand;
const String _openClassesCommand =
    PreConnectBrowserActionIds.openClassesCommand;
const String _openExamsCommand = PreConnectBrowserActionIds.openExamsCommand;
const String _openFriendsScheduleCommand =
    PreConnectBrowserActionIds.openFriendsScheduleCommand;
const String _openShareScheduleCommand =
    PreConnectBrowserActionIds.openShareScheduleCommand;
const String _openScanScheduleCommand =
    PreConnectBrowserActionIds.openScanScheduleCommand;
const String _openSeatStatusCommand =
    PreConnectBrowserActionIds.openSeatStatusCommand;
const String _menuRootId = PreConnectBrowserActionIds.menuRootId;
const String _menuSidePanelId = PreConnectBrowserActionIds.menuSidePanelId;
const String _menuDashboardId = PreConnectBrowserActionIds.menuDashboardId;
const String _menuProfileId = PreConnectBrowserActionIds.menuProfileId;
const String _menuClassesId = PreConnectBrowserActionIds.menuClassesId;
const String _menuExamsId = PreConnectBrowserActionIds.menuExamsId;
const String _menuFriendsId = PreConnectBrowserActionIds.menuFriendsId;
const String _menuShareId = PreConnectBrowserActionIds.menuShareId;
const String _menuScanId = PreConnectBrowserActionIds.menuScanId;
const String _menuSeatStatusId = PreConnectBrowserActionIds.menuSeatStatusId;
const String _shortcutCustomSchedule =
    PreConnectBrowserActionIds.shortcutCustomSchedule;
const String _shortcutProfile = PreConnectBrowserActionIds.shortcutProfile;
const String _shortcutClasses = PreConnectBrowserActionIds.shortcutClasses;
const String _shortcutExams = PreConnectBrowserActionIds.shortcutExams;
const String _shortcutFriends = PreConnectBrowserActionIds.shortcutFriends;
const String _shortcutShare = PreConnectBrowserActionIds.shortcutShare;
const String _shortcutScan = PreConnectBrowserActionIds.shortcutScan;
const String _shortcutSeatStatus =
    PreConnectBrowserActionIds.shortcutSeatStatus;
const String _cookieSnapshotConnectKey = 'preconnect.cookies.connect';
const String _cookieSnapshotSsoKey = 'preconnect.cookies.sso';
const String _cookieSnapshotUpdatedAtKey = 'preconnect.cookies.updatedAt';
const String _cachedUnreadCountKey = 'preconnect.cachedUnreadCount';
const String _notificationPayloadsKey = 'preconnect.notificationPayloads';
const String _gcmLastRegisteredAtKey = 'preconnect.gcmLastRegisteredAt';
const String _gcmLastMessageAtKey = 'preconnect.gcmLastMessageAt';
const String _gcmLastDeletedAtKey = 'preconnect.gcmLastDeletedAt';
const String _gcmLastSendErrorKey = 'preconnect.gcmLastSendError';
const String _extensionAlarmId = 'preconnect.syncAlarm';
const String _connectCookieUrl = 'https://connect.bracu.ac.bd/';
const String _ssoCookieUrl =
    'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/';

@JS('fetch')
external JSPromise<Response> _fetch(String input, [RequestInit? init]);

Headers _headersFromMap(Map<String, String> values) {
  final headers = Headers();
  for (final entry in values.entries) {
    headers.append(entry.key, entry.value);
  }
  return headers;
}

Future<void> main() async {
  if (chrome.cookies.isAvailable) {
    chrome.cookies.onChanged.listen((changeInfo) {
      final cookie = changeInfo.cookie;
      final domain = cookie.domain.toLowerCase();
      if (!domain.contains('bracu.ac.bd')) return;
      if (!domain.contains('connect.bracu.ac.bd') &&
          !domain.contains('sso.bracu.ac.bd')) {
        return;
      }
      unawaited(_guarded(_syncBracuCookieSnapshot));
    });
  }

  chrome.runtime.onStartup.listen((_) {
    unawaited(
      _guarded(() async {
        await _bootstrapSessionSync();
        await _configureAlarms();
        await _refreshBadgeAndNotifyIfNeeded();
        await _registerGcmAndSyncToken();
        await _restoreAppTabAfterStartup();
      }),
    );
  });
  chrome.runtime.onInstalled.listen((_) {
    unawaited(
      _guarded(() async {
        await _bootstrapSessionSync();
        await _configureAlarms();
        await _refreshBadgeAndNotifyIfNeeded();
        await _registerGcmAndSyncToken();
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

  chrome.runtime.onMessage.listen(_handleRuntimeMessage);

  chrome.webNavigation.onCommitted.listen((details) {
    unawaited(_guarded(() => _handleNavigation(details)));
  });

  chrome.tabs.onRemoved.listen((event) {
    unawaited(_guarded(() => _handleTabRemoved(event)));
  });

  if (chrome.alarms.isAvailable) {
    chrome.alarms.onAlarm.listen((alarm) {
      if (alarm.name != _extensionAlarmId) return;
      unawaited(
        _guarded(() async {
          await _syncLatestSession();
          await _refreshBadgeAndNotifyIfNeeded();
          await _registerGcmAndSyncToken();
        }),
      );
    });
  }

  if (chrome.gcm.isAvailable) {
    chrome.gcm.onMessage.listen((event) {
      unawaited(_guarded(() => _handleGcmMessage(event)));
    });
    chrome.gcm.onMessagesDeleted.listen((_) {
      unawaited(_guarded(_handleGcmMessagesDeleted));
    });
    chrome.gcm.onSendError.listen((error) {
      unawaited(_guarded(() => _handleGcmSendError(error)));
    });
  }

  if (chrome.notifications.isAvailable) {
    chrome.notifications.onClicked.listen((notificationId) {
      unawaited(_guarded(() => _handleNotificationClick(notificationId)));
    });
    chrome.notifications.onClosed.listen((event) {
      unawaited(
        _guarded(() => _clearNotificationPayload(event.notificationId)),
      );
    });
  }

  unawaited(_guarded(_configureBrowserSurfaces));
  unawaited(_guarded(_syncBracuCookieSnapshot));
  unawaited(_guarded(_configureAlarms));
  unawaited(_guarded(_refreshBadgeAndNotifyIfNeeded));
  unawaited(_guarded(_bootstrapSessionSync));
  unawaited(_guarded(_registerGcmAndSyncToken));
}

Future<void> _guarded(Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {}
}

void _handleRuntimeMessage(dynamic event) {
  final message = event.message;
  if (message is! Map) return;
  final type = '${message['type'] ?? ''}';
  Future<void> Function()? action;
  switch (type) {
    case _startLoginType:
      action = _startLogin;
      break;
    case _startLogoutType:
      action = _startLogout;
      break;
    case PreConnectPushConfig.syncPushTokenMessageType:
      action = _registerGcmAndSyncToken;
      break;
    default:
      return;
  }
  try {
    event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
  } catch (_) {}
  unawaited(_guarded(action));
}

Future<void> _syncBracuCookieSnapshot() async {
  if (!chrome.cookies.isAvailable) return;

  final connectCookies = await chrome.cookies.getAll(
    ck.GetAllDetails(url: _connectCookieUrl),
  );
  final ssoCookies = await chrome.cookies.getAll(
    ck.GetAllDetails(url: _ssoCookieUrl),
  );

  await chrome.storage.local.set({
    _cookieSnapshotConnectKey: jsonEncode(
      connectCookies.map(_cookieToJson).toList(),
    ),
    _cookieSnapshotSsoKey: jsonEncode(ssoCookies.map(_cookieToJson).toList()),
    _cookieSnapshotUpdatedAtKey: DateTime.now().toIso8601String(),
  });
}

Map<String, Object?> _cookieToJson(ck.Cookie cookie) {
  return <String, Object?>{
    'name': cookie.name,
    'value': cookie.value,
    'domain': cookie.domain,
    'path': cookie.path,
    'secure': cookie.secure,
    'httpOnly': cookie.httpOnly,
    'sameSite': cookie.sameSite.value,
    'session': cookie.session,
    'expirationDate': cookie.expirationDate,
    'storeId': cookie.storeId,
    'hostOnly': cookie.hostOnly,
    if (cookie.partitionKey != null)
      'partitionKey': <String, Object?>{
        if (cookie.partitionKey!.topLevelSite != null)
          'topLevelSite': cookie.partitionKey!.topLevelSite,
      },
  };
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

Future<void> _activateBrowserShortcut(String shortcut, {Tab? tab}) async {
  await _persistPendingShortcutAction(shortcut);
  unawaited(
    _broadcastRuntimeMessage({
      'type': _browserShortcutType,
      'shortcut': shortcut,
    }),
  );
  await _openSidePanel(tab: tab);
}

Future<void> _persistPendingShortcutAction(String shortcut) async {
  await chrome.storage.local.set({
    PreConnectStorageKeys.pendingShortcutAction: shortcut,
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

bool _isLogoutUrl(String? url) {
  final uri = Uri.tryParse(url ?? '');
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'sso.bracu.ac.bd' &&
      uri.path.contains('/protocol/openid-connect/logout');
}

Future<void> _autoClickLogoutIfNeeded(int? tabId, {String? url}) async {
  if (!chrome.scripting.isAvailable || tabId == null || !_isLogoutUrl(url)) {
    return;
  }
  try {
    await chrome.scripting.executeScript(
      scripting.ScriptInjection(
        target: scripting.InjectionTarget(tabId: tabId),
        files: const ['auto_click_logout.js'],
        injectImmediately: true,
      ),
    );
  } catch (_) {}
}

Future<void> _configureAlarms() async {
  if (!chrome.alarms.isAvailable) return;
  await chrome.alarms.create(
    _extensionAlarmId,
    alarms.AlarmCreateInfo(periodInMinutes: 5),
  );
}

Future<void> _refreshBadgeAndNotifyIfNeeded() async {
  await _refreshBadge();
  await _maybeNotifyUnreadChange();
}

Future<void> _refreshBadge() async {
  if (!chrome.action.isAvailable) return;
  try {
    final count = await _fetchUnreadCount();
    await chrome.storage.local.set({_cachedUnreadCountKey: count});
    if (count > 0) {
      await chrome.action.setBadgeBackgroundColor(
        action.SetBadgeBackgroundColorDetails(color: [214, 59, 59, 255]),
      );
      await chrome.action.setBadgeText(
        action.SetBadgeTextDetails(text: count > 9 ? '9+' : '$count'),
      );
      await chrome.action.setTitle(
        action.SetTitleDetails(
          title:
              'PreConnect - $count unread notification${count == 1 ? '' : 's'}',
        ),
      );
    } else {
      await chrome.action.setBadgeText(action.SetBadgeTextDetails(text: ''));
      await chrome.action.setTitle(action.SetTitleDetails(title: 'PreConnect'));
    }
  } catch (_) {}
}

Future<void> _maybeNotifyUnreadChange() async {
  if (!chrome.notifications.isAvailable) return;
  try {
    final values = await chrome.storage.local.get(_cachedUnreadCountKey);
    final previous =
        int.tryParse('${values[_cachedUnreadCountKey] ?? ''}') ?? 0;
    final current = await _fetchUnreadCount();
    if (current <= previous) {
      await chrome.storage.local.set({_cachedUnreadCountKey: current});
      return;
    }
    await chrome.storage.local.set({_cachedUnreadCountKey: current});
    final permission = await chrome.notifications.getPermissionLevel();
    if (permission != notifications.PermissionLevel.granted) return;
    await _createChromeNotification(
      'preconnect-unread-$current',
      title: 'New notification update',
      message:
          'You have $current unread notification${current == 1 ? '' : 's'}.',
      requireInteraction: false,
      payload: const <String, String>{'route': 'notifications'},
    );
  } catch (_) {}
}

Future<int> _fetchUnreadCount() async {
  try {
    final response = await _fetch(
      '${ApiConfig.connectApiBase}${ApiConfig.recentNotificationsPath}',
      RequestInit(
        method: 'GET',
        credentials: 'include',
        headers: Headers()..append('Accept', 'application/json'),
      ),
    ).toDart;
    if (response.status != 200) return 0;
    final text = await response.text().toDart;
    final decoded = jsonDecode(text.toDart);
    if (decoded is Map<String, dynamic>) {
      final newCount = decoded['new'];
      if (newCount is num) return newCount.toInt();
    }
  } catch (_) {}
  return 0;
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
    PreConnectStorageKeys.accessToken,
    PreConnectStorageKeys.refreshToken,
  ]);
  final accessToken = '${values[PreConnectStorageKeys.accessToken] ?? ''}'
      .trim();
  final refreshToken = '${values[PreConnectStorageKeys.refreshToken] ?? ''}'
      .trim();
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
    bool tabExists = false;
    if (pending.tabId > 0) {
      try {
        final tab = await chrome.tabs.get(pending.tabId);
        if (tab.id != null) {
          tabExists = true;
        }
      } catch (_) {}
    }
    if (tabExists) {
      await _broadcastFailure('A login flow is already running.');
      return;
    } else {
      await _clearPendingLogin();
    }
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
    await chrome.runtime.sendMessage(null, {
      'type': _loginStartedType,
      'tabId': tab.id,
    }, null);
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
  await ensureFreshWebExtensionSession(forceRefresh: true);
  await _revokeMercureSession();
  final values = await chrome.storage.local.get(PreConnectStorageKeys.idToken);
  final idToken = '${values[PreConnectStorageKeys.idToken] ?? ''}'.trim();
  final logoutUrl = BracuLogout.ssoLogoutUri(idToken: idToken);

  final tab = await chrome.tabs.create(
    CreateProperties(url: logoutUrl.toString(), active: true),
  );
  final logoutTabId = tab.id;
  if (appTabId == null || logoutTabId == null) {
    await _completeMercureLogout(appTabId);
    return;
  }

  await chrome.storage.session.set({
    _pendingLogoutKey: {
      'appTabId': appTabId,
      'logoutTabId': logoutTabId,
      'startedAtMillis': DateTime.now().millisecondsSinceEpoch,
    },
  });

  await _autoClickLogoutIfNeeded(logoutTabId, url: logoutUrl.toString());
}

Future<void> _revokeMercureSession() async {
  try {
    final values = await chrome.storage.local.get(
      PreConnectStorageKeys.accessToken,
    );
    final accessToken = '${values[PreConnectStorageKeys.accessToken] ?? ''}'
        .trim();
    final uri = BracuLogout.mercureLogoutUri;
    final headers = _headersFromMap(
      BracuLogout.mercureLogoutHeaders(accessToken: accessToken),
    );
    await _fetch(
      uri.toString(),
      RequestInit(method: 'DELETE', credentials: 'include', headers: headers),
    ).toDart;
  } catch (_) {}
}

Future<void> _completeMercureLogout(int? appTabId) async {
  await _unregisterGcmToken();
  await _clearPendingLogout();
  await chrome.storage.local.remove([
    PreConnectStorageKeys.accessToken,
    PreConnectStorageKeys.refreshToken,
    PreConnectStorageKeys.idToken,
    PreConnectStorageKeys.cachedHasAuthSession,
    _cookieSnapshotConnectKey,
    _cookieSnapshotSsoKey,
    _cookieSnapshotUpdatedAtKey,
    _cachedUnreadCountKey,
    _gcmLastRegisteredAtKey,
    _gcmLastMessageAtKey,
    _gcmLastDeletedAtKey,
    _gcmLastSendErrorKey,
  ]);
  await chrome.storage.session.remove(_notificationPayloadsKey);
  if (chrome.action.isAvailable) {
    await chrome.action.setBadgeText(action.SetBadgeTextDetails(text: ''));
    await chrome.action.setTitle(action.SetTitleDetails(title: 'PreConnect'));
  }
  if (appTabId != null) {
    try {
      await chrome.tabs.update(appTabId, UpdateProperties(active: true));
    } catch (_) {}
  }
  unawaited(_broadcastRuntimeMessage({'type': _logoutCompleteType}));
}

Future<void> _handleNavigation(OnCommittedDetails details) async {
  if (await _handleLogoutNavigation(details)) {
    return;
  }

  await _autoClickLogoutIfNeeded(details.tabId, url: details.url);

  final pending = await _loadPendingLogin();
  if (pending == null || pending.tabId != details.tabId) return;
  final uri = Uri.tryParse(details.url);
  if (uri == null) return;
  if (uri.scheme != 'https') return;
  if (uri.host != 'connect.bracu.ac.bd') return;
  if (!uri.path.contains('/student/profile/overview')) return;

  final code = uri.queryParameters['code']?.trim() ?? '';
  if (code.isEmpty) {
    await _failAndClear(
      'Login callback did not include an authorization code.',
    );
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
      PreConnectStorageKeys.accessToken: tokens.accessToken,
      PreConnectStorageKeys.refreshToken: tokens.refreshToken,
      if (tokens.idToken.isNotEmpty)
        PreConnectStorageKeys.idToken: tokens.idToken,
      PreConnectStorageKeys.cachedHasAuthSession: 'true',
    });
    await _syncBracuCookieSnapshot();
    await _refreshBadgeAndNotifyIfNeeded();
    await _clearPendingLogin();
    unawaited(_registerGcmAndSyncToken());
    if (!chrome.sidePanel.isAvailable) {
      unawaited(_openOrFocusAppTab());
    }
    await chrome.runtime.sendMessage(null, {
      'type': _loginCompleteType,
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
    }, null);
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

  if (!BracuLogout.isConnectLogoutRedirect(details.url)) return false;

  await _unregisterGcmToken();
  await _clearPendingLogout();
  await chrome.storage.local.remove([
    PreConnectStorageKeys.accessToken,
    PreConnectStorageKeys.refreshToken,
    PreConnectStorageKeys.idToken,
    PreConnectStorageKeys.cachedHasAuthSession,
    _cookieSnapshotConnectKey,
    _cookieSnapshotSsoKey,
    _cookieSnapshotUpdatedAtKey,
    _cachedUnreadCountKey,
    _gcmLastRegisteredAtKey,
    _gcmLastMessageAtKey,
    _gcmLastDeletedAtKey,
    _gcmLastSendErrorKey,
  ]);
  await chrome.storage.session.remove(_notificationPayloadsKey);
  if (chrome.action.isAvailable) {
    await chrome.action.setBadgeText(action.SetBadgeTextDetails(text: ''));
    await chrome.action.setTitle(action.SetTitleDetails(title: 'PreConnect'));
  }
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
  } catch (_) {}
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
    required this.idToken,
  });

  final String accessToken;
  final String refreshToken;
  final String idToken;
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
      headers: Headers()
        ..append('Content-Type', 'application/x-www-form-urlencoded'),
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
  final idToken = '${decoded['id_token'] ?? ''}';
  if (accessToken.isEmpty || refreshToken.isEmpty) {
    throw const FormatException(
      'Token response missing access or refresh token',
    );
  }
  return _TokenResponse(
    accessToken: accessToken,
    refreshToken: refreshToken,
    idToken: idToken,
  );
}

Future<void> _registerGcmAndSyncToken() async {
  if (!chrome.gcm.isAvailable) return;
  await ensureFreshWebExtensionSession();
  final hasSession = await _hasStoredAuthSession();
  if (!hasSession) return;

  try {
    final token = await chrome.gcm.register([PreConnectPushConfig.gcmSenderId]);
    if (token.isNotEmpty) {
      await chrome.storage.local.set({PreConnectPushConfig.gcmTokenKey: token});
      await chrome.storage.local.set({
        _gcmLastRegisteredAtKey: DateTime.now().toIso8601String(),
      });
      await _registerFcmTokenWithBackend(token);
      await _syncPushTopics(token);
    }
  } catch (_) {}
}

Future<void> _registerFcmTokenWithBackend(String token) async {
  await _postPushJson(
    PreConnectPushConfig.registerDevicePath,
    <String, dynamic>{
      'token': token,
      'platform': PreConnectPushConfig.chromeExtensionPlatform,
    },
  );
}

Future<void> _syncPushTopics(String token) async {
  final topics = <String>{
    ...PreConnectPushConfig.defaultTopics,
    ...await _loadPinnedSeatTopics(),
  };
  for (final topic in topics) {
    await _postPushJson(
      PreConnectPushConfig.subscribeTopicPath,
      <String, dynamic>{'token': token, 'topic': topic},
    );
  }
}

Future<Set<String>> _loadPinnedSeatTopics() async {
  try {
    final key = PreConnectPushConfig.coursePinsKey(
      PreConnectPushConfig.seatStatusPinScope,
    );
    final values = await chrome.storage.local.get(key);
    final raw = values[key];
    final pins = <String>{};
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        pins.addAll(decoded.map((value) => '$value'));
      }
    } else if (raw is List) {
      pins.addAll(raw.map((value) => '$value'));
    }
    return pins
        .map((pin) => pin.trim().toUpperCase())
        .where((pin) => pin.isNotEmpty)
        .map(PreConnectPushConfig.seatTopic)
        .toSet();
  } catch (_) {
    return const <String>{};
  }
}

Future<void> _postPushJson(
  String path,
  Map<String, dynamic> body, {
  String? accessToken,
}) async {
  try {
    var token = accessToken?.trim() ?? '';
    if (token.isEmpty) {
      final values = await chrome.storage.local.get(
        PreConnectStorageKeys.accessToken,
      );
      token = '${values[PreConnectStorageKeys.accessToken] ?? ''}'.trim();
    }
    if (token.isEmpty) return;

    await _fetch(
      '${ApiConfig.realtimeApiBase}$path',
      RequestInit(
        method: 'POST',
        headers: _headersFromMap(<String, String>{
          ...ApiConfig.apiHeaders,
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
        body: jsonEncode(body).toJS,
      ),
    ).toDart;
  } catch (_) {}
}

Future<void> _unregisterGcmToken() async {
  if (!chrome.gcm.isAvailable) return;
  try {
    final storedValues = await chrome.storage.local.get(
      PreConnectPushConfig.gcmTokenKey,
    );
    var token = '${storedValues[PreConnectPushConfig.gcmTokenKey] ?? ''}'
        .trim();
    if (token.isEmpty) {
      token = await chrome.gcm.register([PreConnectPushConfig.gcmSenderId]);
    }
    if (token.isNotEmpty) {
      final values = await chrome.storage.local.get(
        PreConnectStorageKeys.accessToken,
      );
      final accessToken = '${values[PreConnectStorageKeys.accessToken] ?? ''}'
          .trim();
      if (accessToken.isNotEmpty) {
        await _postPushJson(
          PreConnectPushConfig.unregisterDevicePath,
          <String, dynamic>{'token': token},
          accessToken: accessToken,
        );
      }
    }
  } catch (_) {}
  try {
    await chrome.gcm.unregister();
  } catch (_) {}
  try {
    await chrome.storage.local.remove(PreConnectPushConfig.gcmTokenKey);
  } catch (_) {}
}

Future<void> _handleGcmMessage(OnMessageMessage event) async {
  await chrome.storage.local.set({
    _gcmLastMessageAtKey: DateTime.now().toIso8601String(),
  });
  final data = _normalizeGcmPayload(event.data);
  final title = _firstPayloadText(data, const <String>[
    'title',
    'notification.title',
    'gcm.notification.title',
  ], fallback: 'PreConnect');
  var body = _firstPayloadText(data, const <String>[
    'body',
    'message',
    'notification.body',
    'gcm.notification.body',
  ]);
  final courseCode = _firstPayloadText(data, const <String>['courseCode']);
  final sectionName = _firstPayloadText(data, const <String>['sectionName']);
  if (body.isEmpty && courseCode.isNotEmpty) {
    final section = sectionName.isEmpty ? '' : ' Section $sectionName';
    body = 'Seat update available for $courseCode$section.';
  }

  if (body.isEmpty) return;

  final notificationId = 'fcm-${DateTime.now().millisecondsSinceEpoch}';
  await _createChromeNotification(
    notificationId,
    title: title,
    message: body,
    requireInteraction: true,
    payload: data,
  );
  unawaited(_refreshBadge());
}

Future<void> _handleGcmMessagesDeleted() async {
  await chrome.storage.local.set({
    _gcmLastDeletedAtKey: DateTime.now().toIso8601String(),
  });
  await _refreshBadgeAndNotifyIfNeeded();
}

Future<void> _handleGcmSendError(OnSendErrorError error) async {
  await chrome.storage.local.set({
    _gcmLastSendErrorKey: jsonEncode(<String, String>{
      'at': DateTime.now().toIso8601String(),
      'messageId': error.messageId ?? '',
      'errorMessage': error.errorMessage,
    }),
  });
}

Map<String, String> _normalizeGcmPayload(Map data) {
  final normalized = <String, String>{};
  for (final entry in data.entries) {
    final key = '${entry.key}'.trim();
    if (key.isEmpty) continue;
    normalized[key] = '${entry.value ?? ''}'.trim();
  }
  return normalized;
}

String _firstPayloadText(
  Map<String, String> data,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = data[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}

Future<void> _createChromeNotification(
  String notificationId, {
  required String title,
  required String message,
  required bool requireInteraction,
  Map<String, String> payload = const <String, String>{},
}) async {
  if (!chrome.notifications.isAvailable) return;
  try {
    final permission = await chrome.notifications.getPermissionLevel();
    if (permission != notifications.PermissionLevel.granted) return;
  } catch (_) {}
  if (payload.isNotEmpty) {
    await _saveNotificationPayload(notificationId, payload);
  }
  await chrome.notifications.create(
    notificationId,
    notifications.NotificationOptions(
      type: notifications.TemplateType.basic,
      iconUrl: chrome.runtime.getURL('icons/icon-128.png'),
      title: title,
      message: message,
      priority: 0,
      requireInteraction: requireInteraction,
    ),
  );
}

Future<void> _saveNotificationPayload(
  String notificationId,
  Map<String, String> payload,
) async {
  try {
    final values = await chrome.storage.session.get(_notificationPayloadsKey);
    final raw = values[_notificationPayloadsKey];
    final payloads = <String, Object?>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        payloads['${entry.key}'] = entry.value;
      }
    }
    payloads[notificationId] = payload;
    await _writeNotificationPayloads(payloads);
  } catch (_) {}
}

Future<Map<String, String>> _takeNotificationPayload(
  String notificationId,
) async {
  try {
    final values = await chrome.storage.session.get(_notificationPayloadsKey);
    final raw = values[_notificationPayloadsKey];
    if (raw is! Map) return const <String, String>{};
    final payloads = <String, Object?>{};
    for (final entry in raw.entries) {
      payloads['${entry.key}'] = entry.value;
    }
    final payload = payloads.remove(notificationId);
    await _writeNotificationPayloads(payloads);
    if (payload is! Map) return const <String, String>{};
    final normalized = <String, String>{};
    for (final entry in payload.entries) {
      normalized['${entry.key}'] = '${entry.value ?? ''}'.trim();
    }
    return normalized;
  } catch (_) {
    return const <String, String>{};
  }
}

Future<void> _clearNotificationPayload(String notificationId) async {
  try {
    final values = await chrome.storage.session.get(_notificationPayloadsKey);
    final raw = values[_notificationPayloadsKey];
    if (raw is! Map) return;
    final payloads = <String, Object?>{};
    for (final entry in raw.entries) {
      payloads['${entry.key}'] = entry.value;
    }
    payloads.remove(notificationId);
    await _writeNotificationPayloads(payloads);
  } catch (_) {}
}

Future<void> _writeNotificationPayloads(Map<String, Object?> payloads) async {
  if (payloads.isEmpty) {
    await chrome.storage.session.remove(_notificationPayloadsKey);
    return;
  }
  await chrome.storage.session.set({_notificationPayloadsKey: payloads});
}

String _notificationShortcutForPayload(Map<String, String> payload) {
  final explicitRoute = _firstPayloadText(payload, const <String>['route']);
  if (explicitRoute == 'notifications') {
    return PreConnectBrowserActionIds.shortcutNotifications;
  }
  final courseCode = _firstPayloadText(payload, const <String>['courseCode']);
  if (courseCode.isNotEmpty) {
    return PreConnectBrowserActionIds.shortcutSeatStatus;
  }
  return PreConnectBrowserActionIds.shortcutNotifications;
}

String _notificationUrlForPayload(Map<String, String> payload) {
  return _firstPayloadText(payload, const <String>[
    'url',
    'link',
    'click_action',
    'gcm.notification.click_action',
  ]);
}

Future<bool> _openNotificationUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  try {
    await chrome.tabs.create(
      CreateProperties(url: uri.toString(), active: true),
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _handleNotificationClick(String notificationId) async {
  try {
    await chrome.notifications.clear(notificationId);
  } catch (_) {}
  final payload = await _takeNotificationPayload(notificationId);
  final url = _notificationUrlForPayload(payload);
  if (url.isNotEmpty && await _openNotificationUrl(url)) return;
  await _activateBrowserShortcut(_notificationShortcutForPayload(payload));
}
