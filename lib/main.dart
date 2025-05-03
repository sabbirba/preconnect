import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'pages/home.dart';
import 'pages/login.dart';

void main() async {
  // This needs to be called before any platform channel calls
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AndroidAlarmManager
  await AndroidAlarmManager.initialize();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Dummy login status. Replace with actual login check logic.
  final bool isLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student App',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: isLoggedIn ? HomeScreen() : LoginScreen(),
    );
  }
}
