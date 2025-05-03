import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ExamSchedulePage extends StatefulWidget {
  @override
  _ExamSchedulePageState createState() => _ExamSchedulePageState();
}

class _ExamSchedulePageState extends State<ExamSchedulePage> {
  final _storage = FlutterSecureStorage();
  bool _loading = true;
  List<dynamic> _courses = [];
  List<Map<String, String>> _midtermExams = [];
  List<Map<String, String>> _finalExams = [];

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
        _organizeExamSchedules(data);
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

  void _organizeExamSchedules(List<dynamic> courses) {
    final midterms = <Map<String, String>>[];
    final finals = <Map<String, String>>[];

    for (final course in courses) {
      final courseCode = course['courseCode'];
      final sectionSchedule = jsonDecode(course['sectionSchedule']);
      final finalExamDate = sectionSchedule['finalExamDate'];
      final midExamDate = sectionSchedule['midExamDate'];

      if (finalExamDate != null) {
        finals.add({
          'course': courseCode,
          'examType': 'Final Exam',
          'date': finalExamDate,
        });
      }
      if (midExamDate != null) {
        midterms.add({
          'course': courseCode,
          'examType': 'Mid Exam',
          'date': midExamDate,
        });
      }
    }

    setState(() {
      _midtermExams = midterms;
      _finalExams = finals;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        if (_midtermExams.isNotEmpty)
          _buildExamGroup('Midterm Exams', _midtermExams),
        if (_finalExams.isNotEmpty) _buildExamGroup('Final Exams', _finalExams),
        if (_midtermExams.isEmpty && _finalExams.isEmpty)
          Center(child: Text('No exams scheduled.')),
      ],
    );
  }

  Widget _buildExamGroup(String title, List<Map<String, String>> exams) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        ...exams
            .map(
              (exam) => Card(
                elevation: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(Icons.event),
                  title: Text('${exam['course']}'),
                  subtitle: Text('${exam['examType']} on ${exam['date']}'),
                ),
              ),
            )
            .toList(),
        SizedBox(height: 16),
      ],
    );
  }
}
