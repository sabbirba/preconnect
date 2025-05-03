import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class SemesterCalendarPage extends StatefulWidget {
  @override
  _SemesterCalendarPageState createState() => _SemesterCalendarPageState();
}

class _SemesterCalendarPageState extends State<SemesterCalendarPage> {
  Map<DateTime, List<String>> _events = {};
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  String _currentSemester = 'Spring 2025';

  @override
  void initState() {
    super.initState();
    _loadSemesterAndEvents();
  }

  Future<void> _loadSemesterAndEvents() async {
    final prefs = await SharedPreferences.getInstance();
    _currentSemester = prefs.getString("currentSemester") ?? 'Spring 2025';

    // Parse semester name and year
    final parts = _currentSemester.split(' ');
    if (parts.length != 2) return;

    final semester = parts[0].toLowerCase(); // spring
    final year = parts[1]; // 2025

    final url = 'https://www.bracu.ac.bd/academic/$semester/$year/rss.xml';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final document = xml.XmlDocument.parse(response.body);
      final events = document.findAllElements('event');

      Map<DateTime, List<String>> parsedEvents = {};

      for (var event in events) {
        final title = event.getElement('title')?.text.trim() ?? '';
        final startDateStr = event.getElement('start-date')?.text.trim() ?? '';
        final endDateStr = event.getElement('end-date')?.text.trim() ?? '';

        final startDate = _parseDate(startDateStr);
        final endDate = _parseDate(endDateStr);

        if (startDate != null && endDate != null) {
          for (
            DateTime date = startDate;
            !date.isAfter(endDate);
            date = date.add(Duration(days: 1))
          ) {
            final key = DateTime(date.year, date.month, date.day);
            parsedEvents.putIfAbsent(key, () => []).add(title);
          }
        }
      }

      setState(() {
        _events = parsedEvents;
      });
    } else {
      print("Failed to fetch semester calendar");
    }
  }

  DateTime? _parseDate(String dateTimeStr) {
    try {
      final parts = dateTimeStr.split(' - ');
      final dateParts = parts[0].split('/');
      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2026),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: _getEventsForDay,
            calendarFormat: _calendarFormat,
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            calendarStyle: CalendarStyle(
              markerDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                _getEventsForDay(_selectedDay).isEmpty
                    ? Center(child: Text("No events"))
                    : ListView(
                      children:
                          _getEventsForDay(_selectedDay)
                              .map((event) => ListTile(title: Text(event)))
                              .toList(),
                    ),
          ),
        ],
      ),
    );
  }
}
