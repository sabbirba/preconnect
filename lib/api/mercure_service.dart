import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class MercureService {
  static final MercureService instance = MercureService._internal();
  factory MercureService() => instance;
  MercureService._internal();

  StreamSubscription<String>? _subscription;
  http.Client? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    try {
      final token = await ApiClient().getAccessToken();
      if (token == null || token.isEmpty) {
        _isConnecting = false;
        return;
      }

      final url = Uri.parse(ApiConfig.connectMercureHubUrl);
      final request = http.Request('GET', url);
      request.headers['accept'] = 'text/event-stream';
      request.headers['authorization'] = 'Bearer $token';
      request.headers['x-realm'] = 'bracu';
      request.headers['x-source'] = '3';
      request.headers['cache-control'] = 'no-cache';

      _client = HttpUtils.client;
      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;
        _isConnecting = false;

        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleSseLine,
              onError: (error) {
                _handleDisconnect();
              },
              onDone: () {
                _handleDisconnect();
              },
              cancelOnError: true,
            );
      } else {
        _isConnecting = false;
        _scheduleReconnect();
      }
    } catch (e) {
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _handleSseLine(String line) {
    if (line.startsWith('data: ')) {
      final dataStr = line.substring(6).trim();
      if (dataStr.isEmpty) return;
      try {
        final data = jsonDecode(dataStr);
        _processMercureEvent(data);
      } catch (_) {}
    }
  }

  void _processMercureEvent(dynamic data) {
    if (data is Map<String, dynamic>) {
      final type = (data['type'] ?? data['event'] ?? '').toString();
      RefreshBus.instance.notify(reason: 'mercure_$type');
      if (type.isNotEmpty) {
        RefreshBus.instance.notify(reason: type);
      }
    } else {
      RefreshBus.instance.notify(reason: 'mercure_event');
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _subscription?.cancel();
    _subscription = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client = null;
    _isConnected = false;
    _isConnecting = false;
  }
}
