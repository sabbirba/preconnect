import 'package:flutter/foundation.dart';

enum HomeTab {
  settings,
  dashboard,
  profile,
  studentSchedule,
  examSchedule,
  seatStatus,
  degreeProgress,
  alarms,
  shareSchedule,
  scanSchedule,
  friendSchedule,
  devs,
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
