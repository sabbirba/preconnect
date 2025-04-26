import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

class AlarmsPage extends StatefulWidget {
  @override
  _AlarmsPageState createState() => _AlarmsPageState();
}

class _AlarmsPageState extends State<AlarmsPage> {
  final _storage = FlutterSecureStorage();
  List<dynamic> _courses = [];
  bool _loading = true;
  Map<int, bool> _alarmEnabled = {}; // Maps sectionId -> switch state

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    try {
      final studentPortfolioId = await _storage.read(
        key: 'student_portfolio_id',
      );
      final accessToken = await _storage.read(key: 'access_token');

      final url = Uri.parse(
        'https://connect.bracu.ac.bd/api/adv/v1/student-courses/schedules?studentPortfolioId=$studentPortfolioId',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _courses = jsonDecode(response.body);
          _loading = false;
        });
      } else {
        print('Failed to load courses: ${response.statusCode}');
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      print('Error fetching courses: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _setAlarm(
    List<String> days,
    String startTime,
    String courseCode,
  ) async {
    final timeParts = startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    final dayMapping = {
      'SUNDAY': 1,
      'MONDAY': 2,
      'TUESDAY': 3,
      'WEDNESDAY': 4,
      'THURSDAY': 5,
      'FRIDAY': 6,
      'SATURDAY': 7,
    };

    final alarmDays =
        days.map((day) => dayMapping[day]).whereType<int>().toList();

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': '$courseCode Class Reminder',
        'android.intent.extra.alarm.DAYS': alarmDays,
        'android.intent.extra.alarm.SKIP_UI': false,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );

    await intent.launch();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_courses.isEmpty) {
      return Center(child: Text('No courses found.'));
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _courses.length,
      itemBuilder: (context, index) {
        final course = _courses[index];
        final sectionId = course['sectionId'];

        Map<String, dynamic> schedule = {};
        List<dynamic> classSchedules = [];
        try {
          schedule = jsonDecode(course['sectionSchedule'] ?? '{}');
          classSchedules = schedule['classSchedules'] ?? [];
        } catch (e) {
          print('Error decoding sectionSchedule: $e');
        }

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Course Title + Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${course['courseCode']} - Section ${course['sectionName']}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      value: _alarmEnabled[sectionId] ?? false,
                      onChanged: (bool value) async {
                        setState(() {
                          _alarmEnabled[sectionId] = value;
                        });

                        if (value) {
                          if (classSchedules.isNotEmpty) {
                            final startTime =
                                classSchedules[0]['startTime'] ?? '';
                            final days =
                                classSchedules
                                    .map<String>(
                                      (schedule) => schedule['day'] ?? '',
                                    )
                                    .toList();

                            if (startTime.isNotEmpty && days.isNotEmpty) {
                              await _setAlarm(
                                days,
                                startTime,
                                course['courseCode'],
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),
                // Class timings
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      classSchedules.map((schedule) {
                        final day = schedule['day'] ?? '';
                        final startTime = schedule['startTime'] ?? '';
                        final endTime = schedule['endTime'] ?? '';
                        return Text(
                          '$day: $startTime - $endTime',
                          style: TextStyle(fontSize: 14),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
