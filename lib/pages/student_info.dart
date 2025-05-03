import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentInfoPage extends StatefulWidget {
  const StudentInfoPage({super.key});

  @override
  State<StudentInfoPage> createState() => _StudentInfoPageState();
}

class _StudentInfoPageState extends State<StudentInfoPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Future<Map<String, dynamic>>? _studentInfo;

  @override
  void initState() {
    super.initState();
    _studentInfo = _fetchStudentPortfolio();
  }

  Future<Map<String, dynamic>> _fetchStudentPortfolio() async {
    const String apiUrl = "https://connect.bracu.ac.bd/api/mds/v1/portfolios";
    final String? token = await _secureStorage.read(key: 'access_token');

    if (token == null) throw Exception("No access token found");

    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {"User-Agent": "Mozilla/5.0", "Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final List<dynamic> portfolioList = json.decode(response.body);

      if (portfolioList.isEmpty) {
        throw Exception("No portfolio data available");
      }

      final student = portfolioList[0] as Map<String, dynamic>;

      // Save the `id` to secure storage
      await _secureStorage.write(
        key: 'student_portfolio_id',
        value: student['id'].toString(),
      );

      // Save the `currentSemester` to SharedPreferences
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'currentSemester',
        student['currentSemester'] ?? 'N/A',
      );

      return student;
    } else {
      print("Failed to fetch portfolio: ${response.body}");
      throw Exception("Failed to load student portfolio");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _studentInfo,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData) {
          return const Center(child: Text('No student portfolio found.'));
        }

        final data = snapshot.data!;
        final String imageUrl =
            'https://connect.bracu.ac.bd/cdn/img/thumb/${base64.encode(utf8.encode(data['filePath']))}==.jpg';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl, height: 100, width: 100),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Full Name: ${data['fullName']}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text("Student ID: ${data['studentId']}"),
                    Text("Email: ${data['studentEmail']}"),
                    Text("Mobile No: ${data['mobileNo'] ?? 'N/A'}"),
                    Text("Program: ${data['programOrCourse']}"),
                    Text("Current Semester: ${data['currentSemester']}"),
                    // Text("CGPA: ${data['cgpa'] ?? 'N/A'}"),
                    Text("Earned Credits: ${data['earnedCredit']}"),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
