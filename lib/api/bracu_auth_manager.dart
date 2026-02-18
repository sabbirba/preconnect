import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/payment_service.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/attendance_service.dart';

@Deprecated('Use individual service classes instead')
class BracuAuthManager {
  static final BracuAuthManager _instance = BracuAuthManager._internal();
  factory BracuAuthManager() => _instance;
  BracuAuthManager._internal();

  Future<void> login(BuildContext context) => AuthService().login(context);
  Future<void> logout() => AuthService().logout();
  Future<bool> refreshToken() => AuthService().refreshToken();
  Future<bool> isLoggedIn() => AuthService().isLoggedIn();
  Future<bool> ensureSignedIn() => AuthService().ensureSignedIn();
  Future<bool> hasConnection() => ApiClient().hasConnection();
  Future<DateTime> getTokenExpiryTime() => AuthService().getTokenExpiryTime();
  Future<bool> isTokenExpired() => AuthService().isTokenExpired();

  Future<Map<String, String?>?> fetchProfile({
    bool fromGet = false,
    bool retrying = false,
  }) => ProfileService().fetchProfile(fromGet: fromGet);

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) =>
      ProfileService().getProfile(fromFetch: fromFetch);

  Future<String?> fetchPaymentInfo({
    bool fromGet = false,
    bool retrying = false,
  }) => PaymentService().fetchPaymentInfo(fromGet: fromGet);

  Future<String?> getPaymentInfo({bool fromFetch = false}) =>
      PaymentService().getPaymentInfo(fromFetch: fromFetch);

  Future<Map<String, String?>?> fetchAdvisingInfo({
    bool fromGet = false,
    bool retrying = false,
  }) => AdvisingService().fetchAdvisingInfo(fromGet: fromGet);

  Future<Map<String, String?>?> getAdvisingInfo({bool fromFetch = false}) =>
      AdvisingService().getAdvisingInfo(fromFetch: fromFetch);

  Future<String?> fetchStudentSchedule({
    bool fromGet = false,
    bool retrying = false,
  }) => ScheduleService().fetchStudentSchedule(fromGet: fromGet);

  Future<String?> getStudentSchedule({bool fromFetch = false}) =>
      ScheduleService().getStudentSchedule(fromFetch: fromFetch);

  Future<String?> fetchAttendanceInfo({
    bool fromGet = false,
    bool retrying = false,
  }) => AttendanceService().fetchAttendanceInfo(fromGet: fromGet);

  Future<String?> getAttendanceInfo({bool fromFetch = false}) =>
      AttendanceService().getAttendanceInfo(fromFetch: fromFetch);
}
