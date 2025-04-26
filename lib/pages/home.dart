import 'package:flutter/material.dart';
import 'student_info.dart';
import 'class_schedule.dart';
import 'alarms.dart';
import 'exam_schedule.dart';
import 'semester_calendar.dart';
import 'do_not_disturb.dart';
import 'login.dart'; // Make sure you have this route set up

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  final List<Widget> pages = [
    StudentInfoPage(),
    ClassSchedulePage(),
    AlarmsPage(),
    ExamSchedulePage(),
    SemesterCalendarPage(),
    DoNotDisturbPage(),
  ];

  final List<String> titles = [
    'Student Info',
    'Class Schedule',
    'Alarms',
    'Exam Schedule',
    'Semester Calendar',
    'Do Not Disturb',
  ];

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Logout'),
              ),
            ],
          ),
    );

    if (shouldLogout == true) {
      // Add logout logic here (e.g., clear tokens)

      // Navigate to login page
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[selectedIndex]),
        leading: Builder(
          builder:
              (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        ),
      ),
      drawer: NavigationDrawer(
        selectedIndex: selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            selectedIndex = index;
          });
          Navigator.pop(context); // close drawer
        },
        children: [
          const NavigationDrawerDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: Text('Student Info'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: Text('Class Schedule'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: Text('Alarms'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: Text('Exam Schedule'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: Text('Semester Calendar'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.do_not_disturb_alt_outlined),
            selectedIcon: Icon(Icons.do_not_disturb),
            label: Text('Do Not Disturb'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Divider(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () => _confirmLogout(context),
            ),
          ),
        ],
      ),
      body: pages[selectedIndex],
    );
  }
}
