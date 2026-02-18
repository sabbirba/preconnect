import 'package:flutter/widgets.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/scan_schedule.dart';

Widget buildScanSchedulePage() => const ScanSchedulePage();

Widget buildFriendSchedulePage(void Function(HomeTab tab) onNavigate) =>
    FriendSchedulePage(onNavigate: onNavigate);

Widget buildAlarmPage() => const AlarmPage();

Widget buildDevsPage() => const DevsPage();
