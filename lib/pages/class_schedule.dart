import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ClassSchedulePage extends StatefulWidget {
  @override
  _ClassSchedulePageState createState() => _ClassSchedulePageState();
}

class _ClassSchedulePageState extends State<ClassSchedulePage> {
  final _storage = FlutterSecureStorage();
  bool _loading = true;
  List<dynamic> _courses = [];
  Map<String, List<Map<String, String>>> _scheduleByDay = {};

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
          'User-Agent': 'Mozilla/5.0',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _organizeSchedule(data);
        setState(() {
          _loading = false;
        });
      } else {
        print('Failed to load courses: ${response.statusCode}');
        setState(() => _loading = false);
      }
    } catch (e) {
      print('Error fetching courses: $e');
      setState(() => _loading = false);
    }
  }

  void _organizeSchedule(List<dynamic> courses) {
    final schedule = <String, List<Map<String, String>>>{};

    for (final course in courses) {
      final courseCode = course['courseCode'];
      final room = course['roomNumber'];
      final sectionSchedule = jsonDecode(course['sectionSchedule']);
      final classSchedules = sectionSchedule['classSchedules'] as List<dynamic>;

      for (final session in classSchedules) {
        final day = session['day'];
        final time = '${session['startTime']} - ${session['endTime']}';

        schedule.putIfAbsent(day, () => []).add({
          'time': time,
          'course': courseCode,
          'room': room ?? 'TBA',
        });
      }
    }

    setState(() {
      _scheduleByDay = schedule;
    });
  }

  IconData _getCourseIcon(String? courseCode) {
    if (courseCode == null) return Icons.school;
    if (courseCode.endsWith('L')) {
      return Icons.science; // Lab
    } else {
      return Icons.menu_book; // Lecture
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_scheduleByDay.isEmpty) {
      return Center(child: Text('No classes scheduled.'));
    }

    final days = [
      'SUNDAY',
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
    ];

    return ListView(
      padding: EdgeInsets.all(16),
      children:
          days
              .where((day) => _scheduleByDay.containsKey(day))
              .map(
                (day) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    ..._scheduleByDay[day]!.map(
                      (entry) => Card(
                        elevation: 4,
                        margin: EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: Icon(
                            _getCourseIcon(entry['course']),
                            // color: Colors.blueAccent,
                          ),
                          title: Text(
                            '${entry['course'] ?? ''} (${entry['room'] ?? ''})',
                          ),
                          subtitle: Text(entry['time'] ?? ''),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                ),
              )
              .toList(),
    );
  }
}
