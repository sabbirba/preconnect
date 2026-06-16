class PreConnectStorageKeys {
  PreConnectStorageKeys._();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String idToken = 'id_token';
  static const String cachedHasAuthSession = 'cached_has_auth_session';
  static const String pendingShortcutAction = 'pending_shortcut_action';
  static const String seatStatusCacheJson = 'seat_status_cache_json';
  static const String seatStatusEtag = 'seat_status_etag';
}

class PreConnectRouteTokens {
  PreConnectRouteTokens._();

  static const String privateAccess = 'secure_access_gate_v1';
}

class PreConnectBrowserActionIds {
  PreConnectBrowserActionIds._();

  static const String openSidePanelCommand = 'open_side_panel';
  static const String openCustomScheduleCommand = 'open_custom_schedule';
  static const String openProfileCommand = 'open_profile';
  static const String openClassesCommand = 'open_classes';
  static const String openExamsCommand = 'open_exams';
  static const String openFriendsScheduleCommand = 'open_friends_schedule';
  static const String openShareScheduleCommand = 'open_share_schedule';
  static const String openScanScheduleCommand = 'open_scan_schedule';
  static const String openSeatStatusCommand = 'open_seat_status';

  static const String menuRootId = 'preconnect.menu.root';
  static const String menuSidePanelId = 'preconnect.menu.sidePanel';
  static const String menuDashboardId = 'preconnect.menu.dashboard';
  static const String menuProfileId = 'preconnect.menu.profile';
  static const String menuClassesId = 'preconnect.menu.classes';
  static const String menuExamsId = 'preconnect.menu.exams';
  static const String menuFriendsId = 'preconnect.menu.friends';
  static const String menuShareId = 'preconnect.menu.share';
  static const String menuScanId = 'preconnect.menu.scan';
  static const String menuSeatStatusId = 'preconnect.menu.seatStatus';

  static const String shortcutCustomSchedule = 'quick.customSchedule';
  static const String shortcutProfile = 'quick.profile';
  static const String shortcutClasses = 'quick.classes';
  static const String shortcutExams = 'quick.exams';
  static const String shortcutFriends = 'quick.friends';
  static const String shortcutShare = 'quick.share';
  static const String shortcutScan = 'quick.scan';
  static const String shortcutSeatStatus = 'quick.seatStatus';
  static const String shortcutNotifications = 'quick.notifications';
}

class PreConnectPushConfig {
  PreConnectPushConfig._();

  static const String gcmSenderId = '53508941136';
  static const String gcmTokenKey = 'preconnect.gcmToken';
  static const String chromeExtensionPlatform = 'chrome_extension';
  static const String syncPushTokenMessageType = 'preconnect.syncPushToken';
  static const String seatStatusPinScope = 'seat_status';
  static const List<String> defaultTopics = <String>['announcements', 'news'];

  static const String registerDevicePath = '/push/device/register';
  static const String unregisterDevicePath = '/push/device/unregister';
  static const String subscribeTopicPath = '/push/topic/subscribe';
  static const String unsubscribeTopicPath = '/push/topic/unsubscribe';
  static const String sendConfirmationPath = '/push/device/send-confirmation';

  static String coursePinsKey(String scope) => 'course_pins_$scope';
  static String seatTopic(String sectionId) => 'seat_${sectionId.trim()}';
}
