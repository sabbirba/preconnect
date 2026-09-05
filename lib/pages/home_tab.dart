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
  friendSchedule,
  campusPrinter,
  devs,
  personalSchedules,
  libSync,
  dspace,
  materials,
  wishlist,
}

class HomeTabRegistry {
  HomeTabRegistry._();

  static final Map<HomeTab, bool Function()> _backHandlers =
      <HomeTab, bool Function()>{};

  static final ValueNotifier<HomeTab> activeTab = ValueNotifier<HomeTab>(
    HomeTab.settings,
  );

  static void setActive(HomeTab tab) {
    if (activeTab.value == tab) return;
    activeTab.value = tab;
  }

  static void registerBackHandler(HomeTab tab, bool Function() handler) {
    _backHandlers[tab] = handler;
  }

  static void unregisterBackHandler(HomeTab tab, bool Function() handler) {
    if (_backHandlers[tab] == handler) {
      _backHandlers.remove(tab);
    }
  }

  static bool handleBack(HomeTab tab) => _backHandlers[tab]?.call() ?? false;
}
