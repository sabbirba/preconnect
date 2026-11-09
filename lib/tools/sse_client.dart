import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/reconnect_backoff.dart';

class SseClient {
  SseClient({
    required this.name,
    required this.request,
    required this.onEvent,
    this.silence,
    Duration minDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 30),
  }) : _backoff = ReconnectBackoff(min: minDelay, max: maxDelay);

  final String name;
  final Future<http.BaseRequest?> Function() request;
  final void Function(String event, String data) onEvent;
  final Duration? silence;
  final ReconnectBackoff _backoff;

  int _generation = 0;
  bool _running = false;
  StreamSubscription<String>? _lines;
  Completer<void>? _finished;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_run(++_generation));
  }

  void stop() {
    _running = false;
    _generation++;
    _backoff.reset();
    unawaited(_lines?.cancel());
    _lines = null;
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
    _finished = null;
  }

  Future<void> _run(int generation) async {
    while (generation == _generation) {
      try {
        final next = await request();
        if (next == null) {
          if (generation == _generation) stop();
          return;
        }
        next.headers['accept'] = 'text/event-stream';
        next.headers['cache-control'] = 'no-cache';
        final response = await HttpUtils.client.send(next);
        if (generation != _generation || response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          if (generation != _generation) return;
          unawaited(AppLog.write('$name stream: ${response.statusCode}'));
          if (const <int>{401, 403}.contains(response.statusCode)) {
            stop();
            return;
          }
        } else {
          _backoff.reset();
          await _consume(response.stream, generation);
        }
      } catch (error) {
        unawaited(AppLog.write('$name stream error: $error'));
      }
      if (generation != _generation) return;
      await Future<void>.delayed(_backoff.next());
    }
  }

  Future<void> _consume(Stream<List<int>> body, int generation) {
    final finished = _finished = Completer<void>();
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    var lines = body.transform(utf8.decoder).transform(const LineSplitter());
    final timeout = silence;
    if (timeout != null) {
      lines = lines.timeout(timeout, onTimeout: (sink) => sink.close());
    }
    var event = '';
    _lines = lines.listen(
      (line) {
        if (generation != _generation) return;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          onEvent(event, line.substring(5).trim());
        } else if (line.isEmpty) {
          event = '';
        }
      },
      onError: (Object _) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    return finished.future;
  }
}
