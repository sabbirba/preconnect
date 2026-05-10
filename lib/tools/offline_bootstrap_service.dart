import 'package:preconnect/api/calendar_service.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/custom_schedules.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';

class OfflineBootstrapService {
  OfflineBootstrapService._();

  static Future<void> warmStartupCaches() async {
    final tasks = <Future<void>>[
      preloadHomeDashboardData().then((_) {}),
      ProfileService().getProfile().then((_) {}),
      AttendanceService().getAttendanceInfo().then((_) {}),
      PaymentService().getPaymentInfo().then((_) {}),
      ProgressService().getProgress().then((_) {}),
      ScheduleService().getCurrentSemesterSections().then((_) {}),
      CustomSchedulesService().getItems().then((_) {}),
      FriendScheduleStore().loadSnapshot().then((_) {}),
      CalendarService().getCalendar().then((_) {}),
      NotificationService().getRecentNotifications().then((_) {}),
      fetchCampusMapData().then((_) {}),
      fetchTransportScheduleUrl().then((_) {}),
      preloadCurrentSessionSemesterId().then((_) {}),
      SeatStatusService.preload(),
      BusPage.preload(),
      NotificationsPage.preload(),
      DegreeProgressPage.preload(),
      StudentProfile.preload(),
      DevsPage.preload(),
      AlarmPage.preload(),
      ClassSchedule.preload(),
      ExamSchedule.preload(),
      CustomSchedulesPage.preload(),
    ];
    await Future.wait(tasks.map((task) => task.catchError((_) {})));
  }
}
