import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/sse_client.dart';

class SeatCount {
  const SeatCount({
    required this.sectionId,
    required this.consumed,
    this.capacity,
  });

  final int sectionId;
  final int consumed;
  final int? capacity;
}

class SeatStream {
  SeatStream._() {
    _controller = StreamController<List<SeatCount>>.broadcast(
      onListen: _client.start,
      onCancel: _client.stop,
    );
  }

  static final SeatStream instance = SeatStream._();

  late final StreamController<List<SeatCount>> _controller;
  late final SseClient _client = SseClient(
    name: 'Seat',
    request: () async =>
        http.Request('GET', Uri.parse(ApiConfig.seatStreamUrl)),
    onEvent: _dispatch,
    silence: const Duration(seconds: 20),
  );

  Stream<List<SeatCount>> get updates => _controller.stream;

  void _dispatch(String event, String data) {
    final counts = parseSeatEvent(event, data);
    if (counts.isNotEmpty) _controller.add(counts);
  }
}

List<SeatCount> parseSeatEvent(String event, String data) {
  try {
    final decoded = jsonDecode(data);
    if (event == 'seat-snapshot' && decoded is Map) {
      return [
        for (final entry in decoded.entries)
          if (int.tryParse('${entry.key}') case final id?)
            if (entry.value case final int consumed)
              SeatCount(sectionId: id, consumed: consumed),
      ];
    }
    if (event == 'section-updated' && decoded is Map) {
      final update = decoded['data'];
      if (update is! Map) return const [];
      final section = (update['section'] as num?)?.toInt();
      final total = (update['total'] as num?)?.toInt();
      if (section == null || total == null) return const [];
      return [
        SeatCount(
          sectionId: section,
          consumed: total,
          capacity: (update['capacity'] as num?)?.toInt(),
        ),
      ];
    }
  } catch (_) {}
  return const [];
}
