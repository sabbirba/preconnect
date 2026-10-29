import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/http/http_utils.dart';

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
      onListen: _open,
      onCancel: _close,
    );
  }

  static final SeatStream instance = SeatStream._();

  static const Duration _minDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static const Duration _silence = Duration(seconds: 20);

  late final StreamController<List<SeatCount>> _controller;
  StreamSubscription<String>? _lines;
  int _generation = 0;

  Stream<List<SeatCount>> get updates => _controller.stream;

  void _open() {
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void _close() {
    _generation++;
    unawaited(_lines?.cancel());
    _lines = null;
  }

  Future<void> _run(int generation) async {
    var delay = _minDelay;
    while (generation == _generation) {
      try {
        final request = http.Request('GET', Uri.parse(ApiConfig.seatStreamUrl))
          ..headers['accept'] = 'text/event-stream'
          ..headers['cache-control'] = 'no-cache';
        final response = await HttpUtils.client.send(request);
        if (generation != _generation) return;
        if (response.statusCode == 200) {
          delay = _minDelay;
          await _consume(response.stream, generation);
        }
      } catch (error) {
        unawaited(AppLog.write('Seat stream error: $error'));
      }
      if (generation != _generation) return;
      await Future<void>.delayed(delay);
      delay = Duration(
        milliseconds: math.min(
          delay.inMilliseconds * 2,
          _maxDelay.inMilliseconds,
        ),
      );
    }
  }

  Future<void> _consume(Stream<List<int>> body, int generation) {
    final finished = Completer<void>();
    var event = '';
    _lines = body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_silence, onTimeout: (sink) => sink.close())
        .listen(
          (line) {
            if (generation != _generation) return;
            if (line.startsWith('event:')) {
              event = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              _dispatch(event, line.substring(5).trim());
            } else if (line.isEmpty) {
              event = '';
            }
          },
          onError: (Object _) {
            if (!finished.isCompleted) finished.complete();
          },
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
          cancelOnError: true,
        );
    return finished.future;
  }

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
