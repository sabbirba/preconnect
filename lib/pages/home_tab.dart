import 'package:flutter/foundation.dart';

enum HomeTab {
  settings,
  notifications,
  dashboard,
  moreQuickAccess,
  freeLabs,
  calendar,
  profile,
  studentSchedule,
  examSchedule,
  seatStatus,
  degreeProgress,
  alarms,
  shareSchedule,
  scanSchedule,
  friendSchedule,
  campusPrinter,
  devs,
  schedulePlanner,
}

class HomeTabRegistry {
  HomeTabRegistry._();

  static final ValueNotifier<HomeTab> activeTab = ValueNotifier<HomeTab>(
    HomeTab.settings,
  );

  static void setActive(HomeTab tab) {
    if (activeTab.value == tab) return;
    activeTab.value = tab;
  }
}
