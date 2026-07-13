import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
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
  String _selectedLibrary = 'Ayesha Abed Library (Main Campus)';
  String? _errorMessage;
  int _capacity = 1;
  late final TextEditingController _capacityController;
  late final FocusNode _capacityFocusNode;

  @override
  void initState() {
    super.initState();
    _capacityController = TextEditingController(text: '1');
    _capacityFocusNode = FocusNode()..addListener(_handleCapacityFocusChange);
    _fetchAvailability();
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _capacityFocusNode.dispose();
    super.dispose();
  }

  void _handleCapacityFocusChange() {
    if (!_capacityFocusNode.hasFocus) {
      final val = _capacityController.text.trim();
      final parsed = int.tryParse(val);
      if (parsed == null || parsed < 1 || parsed > 9) {
        _capacityController.text = _capacity.toString();
      }
    }
  }

  Future<void> _fetchAvailability() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _availabilityData = null;
      _errorMessage = null;
    });

    final dateStr =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    try {
      final data = await LibSyncAuthService.instance.fetchCheckAvailability(
        startDate: dateStr,
        endDate: dateStr,
        startTime: '00:00:00',
        endTime: '23:50:00',
        capacity: _capacity,
        library: _selectedLibrary,
      );

      if (data != null && data.isNotEmpty) {
        final first = data.first;
        if (first is Map &&
            first.containsKey('message') &&
            !first.containsKey('room')) {
          if (mounted) {
            setState(() {
              _errorMessage = first['message'].toString();
              _isLoading = false;
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _availabilityData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 30)),
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

  Future<void> _handleSlotTap(
    Map<String, dynamic> room,
    Map<String, dynamic> slotData,
  ) async {
    final roomNo = room['room_no']?.toString() ?? 'Room';
    final roomCat = room['room_cat']?.toString() ?? 'Study Space';
    final roomId = room['room_id'] as int? ?? 12;
    final slotId = slotData['slot_id'] as int? ?? 7;
    final start = slotData['start_time']?.toString() ?? '';
    final end = slotData['end_time']?.toString() ?? '';
    final timeStr = "${_formatTime(start)} - ${_formatTime(end)}";

    final confirm = await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.bookmark_add_outlined,
      title: 'Confirm Booking?',
      message: 'Book $roomNo ($roomCat) for $timeStr?',
      confirmLabel: 'Book',
      confirmColor: BracuPalette.primary,
      onConfirm: () async {
        try {
          final dateStr =
              "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
          await LibSyncAuthService.instance.holdSlot(
            roomId: roomId,
            date: dateStr,
            slotIds: [slotId],
            memberCount: _capacity,
          );
        } catch (e) {
          if (mounted) {
            showAppSnackBar(
              context,
              e.toString().replaceAll('Exception: ', ''),
            );
          }
          rethrow;
        }
      },
    );

    if (confirm == true) {
      final selfStudentId =
          LibSyncAuthService.instance.state.value.profile?['student_id']
              ?.toString() ??
          '';

      if (_capacity == 1) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
        try {
          await LibSyncAuthService.instance.confirmReservation(
            studentIds: [selfStudentId],
          );
          if (mounted) {
            Navigator.of(context).pop();
            Navigator.of(context).pop(true);
          }
        } catch (e) {
          if (mounted) {
            Navigator.of(context).pop();
            showAppSnackBar(
              context,
              e.toString().replaceAll('Exception: ', ''),
            );
          }
        }
      } else {
        if (!mounted) return;
        final ids = await showDialog<List<String>>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _MemberIdsDialog(
              selfStudentId: selfStudentId,
              totalCapacity: _capacity,
            );
          },
        );

        if (ids != null && ids.isNotEmpty && mounted) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  IconData _getFacilityIcon(String iconClass) {
    if (iconClass.contains('plug')) return Icons.power;
    if (iconClass.contains('lightbulb')) return Icons.lightbulb_outline;
    if (iconClass.contains('wifi')) return Icons.wifi;
    if (iconClass.contains('tv')) return Icons.tv;
    return Icons.star_border;
  }

  void _showHelpBottomSheet(BuildContext context) {
    showBracuBottomSheet<void>(
      context,
      title: 'Libsync Instructions',
      initialChildSize: 0.55,
      builder: (sheetContext, textPrimary, textSecondary) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepItem(
                context,
                stepNumber: '1',
                title: 'Set Booking Settings',
                body:
                    'Choose your reservation date and capacity counter at the top of the availability screen.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '2',
                title: 'Select Campus Location',
                body:
                    'Use the Campus button in the settings row to toggle between Main Campus and Savar Campus availability slots.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '3',
                title: 'Choose Room & Time Slot',
                body:
                    'Browse through the list of rooms and tap on an available time slot to start the reservation workflow.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '4',
                title: 'Hold Slot & Enter Member IDs',
                body:
                    'Tapping a time slot holds it temporarily. A dialog will open where you must enter the student IDs for all members.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '5',
                title: 'Verify & Confirm Booking',
                body:
                    'Tap the Verify button next to each external student ID. Once all member IDs are verified successfully, tap Confirm Booking.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '6',
                title: 'Check In on Campus',
                body:
                    'When you arrive at the library, tap the Check In button on your active reservation card. Ensure you are connected to the campus network.',
              ),
              const Gap(14),
              _buildStepItem(
                context,
                stepNumber: '7',
                title: 'Cancel Booking',
                body:
                    'If your plans change, you can cancel your confirmed reservation from the dashboard to free up slots.',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required String stepNumber,
    required String title,
    required String body,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: BracuPalette.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: BracuPalette.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(4),
              Text(
                body,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);

    final dateDisplay = DateFormat('dd MMM yyyy').format(_selectedDate);
    final errorMessage = _errorMessage;
    final availabilityData = _availabilityData;

    return BracuPageScaffold(
      title: 'Room Availability',
      subtitle: 'Ayesha Abed Library',
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => _showHelpBottomSheet(context),
        ),
      ],
      body: BracuRefreshList(
        onRefresh: _fetchAvailability,
        children: [
          Row(
            children: [
              _CounterControl(
                controller: _capacityController,
                focusNode: _capacityFocusNode,
                onDecrement: _capacity <= 1
                    ? null
                    : () {
                        final next = _capacity - 1;
                        _capacityController.text = next.toString();
                        setState(() {
                          _capacity = next;
                        });
                        _fetchAvailability();
                      },
                onIncrement: _capacity >= 9
                    ? null
                    : () {
                        final next = _capacity + 1;
                        _capacityController.text = next.toString();
                        setState(() {
                          _capacity = next;
                        });
                        _fetchAvailability();
                      },
                onChanged: (val) {
                  final parsed = int.tryParse(val);
                  if (parsed != null && parsed >= 1 && parsed <= 9) {
                    setState(() {
                      _capacity = parsed;
                    });
                    _fetchAvailability();
                  }
                },
              ),
              const Gap(8),
              Expanded(
                flex: 5,
                child: _SelectionButton(
                  label: dateDisplay,
                  onTap: () => _selectDate(context),
                ),
              ),
              const Gap(8),
              Expanded(
                flex: 4,
                child: BracuActionButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedLibrary ==
                          'Ayesha Abed Library (Main Campus)') {
                        _selectedLibrary = 'Ayesha Abed Library (Savar Campus)';
                      } else {
                        _selectedLibrary = 'Ayesha Abed Library (Main Campus)';
                      }
                    });
                    _fetchAvailability();
                  },
                  outlined: true,
                  borderRadius: 4,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  label: _selectedLibrary == 'Ayesha Abed Library (Main Campus)'
                      ? 'Main'
                      : 'Savar',
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Gap(16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorMessage != null)
            BracuEmptyState(message: errorMessage)
          else if (availabilityData == null)
            const BracuEmptyState(
              message: 'Failed to load availability data. Please try again.',
            )
          else if (availabilityData.isEmpty)
            const BracuEmptyState(
              message: 'No available rooms or slots found for this date.',
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: availabilityData.length,
              itemBuilder: (context, index) {
                final item = availabilityData[index];
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
                                  const Gap(2),
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
                          const Gap(6),
                          Text(
                            location,
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const Gap(8),
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
                              return GestureDetector(
                                onTap: () => _handleSlotTap(room, slotData),
                                child: Container(
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

class _CounterControl extends StatelessWidget {
  const _CounterControl({
    required this.controller,
    required this.focusNode,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: BracuActionButton(
            onPressed: onDecrement,
            outlined: false,
            borderRadius: 4,
            padding: EdgeInsets.zero,
            label: '−',
            fontSize: 18,
          ),
        ),
        const Gap(8),
        SizedBox(
          width: 32,
          height: 38,
          child: Center(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[1-9]')),
                LengthLimitingTextInputFormatter(1),
              ],
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              maxLines: 1,
              onChanged: onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BracuPalette.textPrimary(context),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
        const Gap(8),
        SizedBox(
          width: 38,
          height: 38,
          child: BracuActionButton(
            onPressed: onIncrement,
            outlined: false,
            borderRadius: 4,
            padding: EdgeInsets.zero,
            label: '+',
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BracuActionButton(
      onPressed: onTap,
      outlined: true,
      borderRadius: 4,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      label: label,
      fontSize: 13,
    );
  }
}

class _MemberIdsDialog extends StatefulWidget {
  const _MemberIdsDialog({
    required this.selfStudentId,
    required this.totalCapacity,
  });

  final String selfStudentId;
  final int totalCapacity;

  @override
  State<_MemberIdsDialog> createState() => _MemberIdsDialogState();
}

class _MemberIdsDialogState extends State<_MemberIdsDialog> {
  late final List<TextEditingController> _controllers;
  late final List<bool> _verified;
  late final List<String> _names;
  late final List<bool> _loading;
  late final List<String?> _errors;
  bool _isSubmitting = false;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.totalCapacity,
      (index) =>
          TextEditingController(text: index == 0 ? widget.selfStudentId : ''),
    );
    _verified = List.generate(widget.totalCapacity, (index) => index == 0);
    _names = List.generate(
      widget.totalCapacity,
      (index) => index == 0 ? 'You' : '',
    );
    _loading = List.generate(widget.totalCapacity, (_) => false);
    _errors = List.generate(widget.totalCapacity, (_) => null);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyId(int index, String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;
    setState(() {
      _loading[index] = true;
      _errors[index] = null;
      _verified[index] = false;
      _names[index] = '';
    });
    try {
      final res = await LibSyncAuthService.instance.checkMember(cleanId);
      if (!mounted) return;
      setState(() {
        if (res == null) {
          _verified[index] = true;
          _errors[index] = null;
        } else {
          _verified[index] = false;
          _errors[index] = res['status']?.toString() ?? 'Pending approval';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[index] = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading[index] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final allVerified = _verified.every((v) => v);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BracuPalette.card(context),
          border: Border.all(
            color: BracuPalette.textSecondary(context).withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.22
                  : 0.16,
            ),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.group_add_outlined,
                    color: BracuPalette.primary,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      'Enter Member IDs',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.totalCapacity, (index) {
                      final controller = _controllers[index];
                      final isSelf = index == 0;
                      final isLoading = _loading[index];
                      final isVerified = _verified[index];
                      final error = _errors[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSelf ? 'Member 1 (You)' : 'Member ${index + 1}',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Gap(6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    enabled: !isSelf && !isLoading,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Student ID',
                                      hintStyle: TextStyle(
                                        color: textSecondary.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 14,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: textSecondary.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: textSecondary.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: BracuPalette.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (_) {
                                      if (isVerified) {
                                        setState(() {
                                          _verified[index] = false;
                                          _names[index] = '';
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const Gap(8),
                                SizedBox(
                                  height: 42,
                                  child: BracuActionButton(
                                    onPressed: (isLoading || isVerified)
                                        ? null
                                        : () =>
                                              _verifyId(index, controller.text),
                                    isLoading: isLoading,
                                    label: isVerified ? 'Verified' : 'Verify',
                                    icon: isVerified
                                        ? Icons.check_circle_rounded
                                        : Icons.shield_outlined,
                                    outlined: !isVerified,
                                    backgroundColor: isVerified
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : null,
                                    foregroundColor: isVerified
                                        ? Colors.green
                                        : null,
                                    borderRadius: 8,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            if (error != null) ...[
                              const Gap(4),
                              Text(
                                error,
                                style: TextStyle(
                                  color:
                                      error.toLowerCase().contains(
                                            'invitation',
                                          ) ||
                                          error.toLowerCase().contains(
                                            'approve',
                                          )
                                      ? Colors.amber[700]
                                      : Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (_generalError != null) ...[
                const Gap(10),
                Text(
                  _generalError!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Gap(18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BracuActionButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    outlined: true,
                    borderRadius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    label: 'Cancel',
                  ),
                  const Gap(10),
                  BracuActionButton(
                    onPressed: (allVerified && !_isSubmitting)
                        ? () async {
                            final navigator = Navigator.of(context);
                            setState(() {
                              _isSubmitting = true;
                              _generalError = null;
                            });
                            try {
                              final ids = _controllers
                                  .map((c) => c.text.trim())
                                  .toList();
                              await LibSyncAuthService.instance
                                  .confirmReservation(studentIds: ids);
                              if (mounted) {
                                navigator.pop(ids);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _generalError = e.toString().replaceAll(
                                    'Exception: ',
                                    '',
                                  );
                                  _isSubmitting = false;
                                });
                              }
                            }
                          }
                        : null,
                    outlined: false,
                    isLoading: _isSubmitting,
                    borderRadius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    label: 'Confirm Booking',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
