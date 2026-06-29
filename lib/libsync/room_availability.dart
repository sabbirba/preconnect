import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'auth_service.dart';
import 'package:intl/intl.dart';

class RoomAvailabilityPage extends StatefulWidget {
  const RoomAvailabilityPage({super.key});

  @override
  State<RoomAvailabilityPage> createState() => _RoomAvailabilityPageState();
}

class _RoomAvailabilityPageState extends State<RoomAvailabilityPage> {
  DateTime _selectedDate = DateTime.now();
  List<dynamic>? _availabilityData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAvailability();
  }

  Future<void> _fetchAvailability() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _availabilityData = null;
    });

    final dateStr =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    final data = await LibSyncAuthService.instance.fetchCheckAvailability(
      startDate: dateStr,
      endDate: dateStr,
      startTime: '08:00:00',
      endTime: '23:50:00',
    );

    if (mounted) {
      setState(() {
        _availabilityData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      await _fetchAvailability();
    }
  }

  String _formatTime(String rawTime) {
    final parts = rawTime.split(':');
    if (parts.length >= 2) {
      final int hour = int.tryParse(parts[0]) ?? 0;
      final int minute = int.tryParse(parts[1]) ?? 0;
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int formattedHour = hour % 12 == 0 ? 12 : hour % 12;
      final String formattedMinute = minute.toString().padLeft(2, '0');
      return '$formattedHour:$formattedMinute $period';
    }
    return rawTime;
  }

  IconData _getFacilityIcon(String iconClass) {
    if (iconClass.contains('plug')) return Icons.power;
    if (iconClass.contains('lightbulb')) return Icons.lightbulb_outline;
    if (iconClass.contains('wifi')) return Icons.wifi;
    if (iconClass.contains('tv')) return Icons.tv;
    return Icons.star_border;
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);

    final dateDisplay = DateFormat('dd MMM yyyy').format(_selectedDate);

    return BracuPageScaffold(
      title: 'Room Availability',
      subtitle: 'Ayesha Abed Library',
      body: BracuRefreshList(
        onRefresh: _fetchAvailability,
        children: [
          BracuCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Booking Date',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateDisplay,
                          style: TextStyle(
                            fontSize: 18,
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BracuPalette.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const BracuSectionTitle(title: 'Available Rooms & Slots'),
          const SizedBox(height: 10),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_availabilityData == null)
            const BracuEmptyState(
              message: 'Failed to load availability data. Please try again.',
            )
          else if (_availabilityData!.isEmpty)
            const BracuEmptyState(
              message: 'No available rooms or slots found for this date.',
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _availabilityData!.length,
              itemBuilder: (context, index) {
                final item = _availabilityData![index];
                final room = item['room'] as Map<String, dynamic>? ?? {};
                final slots = item['slots'] as List<dynamic>? ?? [];

                final roomNo = room['room_no']?.toString() ?? 'Unknown Room';
                final roomCat = room['room_cat']?.toString() ?? 'Study Space';
                final location = room['location']?.toString() ?? '';
                final facilityList =
                    room['facility_list'] as List<dynamic>? ?? [];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BracuCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    roomNo,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    roomCat,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: BracuPalette.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (facilityList.isNotEmpty)
                              Row(
                                children: facilityList.map<Widget>((fac) {
                                  final iconClass =
                                      fac['icon_class']?.toString() ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(
                                      _getFacilityIcon(iconClass),
                                      size: 16,
                                      color: textSecondary,
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            location,
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Available Slots (24 Hours Format):',
                          style: TextStyle(
                            fontSize: 11,
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (slots.isEmpty)
                          Text(
                            'No active slots available',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: slots.map<Widget>((slotData) {
                              final start =
                                  slotData['start_time']?.toString() ?? '';
                              final end =
                                  slotData['end_time']?.toString() ?? '';
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: BracuPalette.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: BracuPalette.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  "${_formatTime(start)} - ${_formatTime(end)}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: BracuPalette.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
