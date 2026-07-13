import 'package:flutter/foundation.dart';

enum HomeTab {
  settings,
  notifications,
  dashboard,
  bus,
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
  personalSchedules,
  libSync,
  dspace,
  wishlist,
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
