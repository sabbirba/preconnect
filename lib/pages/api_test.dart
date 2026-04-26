import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh_flow.dart';
import 'package:preconnect/tools/token_storage.dart';

class ApiTestPage extends StatefulWidget {
  const ApiTestPage({super.key});

  @override
  State<ApiTestPage> createState() => _ApiTestPageState();
}

class _ApiTestPageState extends State<ApiTestPage> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://connect.bracu.ac.bd/api/adp/v1/staffs/7487',
  );

  final List<String> _methods = const <String>[
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ];

  String _method = 'GET';
  bool _isLoading = false;
  String _responseText = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_isLoading) return;
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      showAppSnackBar(context, 'Enter an endpoint or URL');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final startedAt = DateTime.now();
    final method = _method;

    try {
      var accessToken = await TokenStorage.instance.read(
        key: PreconnectStorageKeys.accessToken,
      );
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found. Login first.');
      }

      final uri = _resolveUri(rawUrl);
      var response = await _perform(
        uri: uri,
        method: method,
        accessToken: accessToken,
      );

      if (response.statusCode == 401) {
        final refreshStatus = await AuthService().refreshTokenStatus();
        if (refreshStatus == TokenRefreshStatus.refreshed) {
          accessToken = await TokenStorage.instance.read(
            key: PreconnectStorageKeys.accessToken,
          );
          if (accessToken != null && accessToken.isNotEmpty) {
            response = await _perform(
              uri: uri,
              method: method,
              accessToken: accessToken,
            );
          }
        }
      }

      final tookMs = DateTime.now().difference(startedAt).inMilliseconds;
      final prettyBody = _prettyBody(response.body);
      setState(() {
        _responseText = prettyBody.isEmpty
            ? '${response.statusCode} ${response.reasonPhrase ?? ''} • ${tookMs}ms'
            : prettyBody;
      });
    } catch (e) {
      setState(() {
        _responseText = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Uri _resolveUri(String rawUrl) {
    final normalized = rawUrl.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return Uri.parse(normalized);
    }
    final path = normalized.startsWith('/') ? normalized : '/$normalized';
    return Uri.parse('${ApiConfig.connectApiBase}$path');
  }

  Future<http.Response> _perform({
    required Uri uri,
    required String method,
    required String accessToken,
  }) async {
    final req = http.Request(method, uri);
    req.headers.addAll(<String, String>{
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    });

    final streamed = await req.send().timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  String _prettyBody(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Connect API Test',
      subtitle: 'BRACU SSO Session',
      icon: Icons.science_outlined,
      body: BracuRefreshList(
        onRefresh: _sendRequest,
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _methods
                      .map(
                        (m) =>
                            DropdownMenuItem<String>(value: m, child: Text(m)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _method = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'https://connect.bracu.ac.bd/api/adp/v1/staffs/7487',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendRequest,
                    icon: _isLoading
                        ? const BracuShimmer(
                            child: BracuSkeletonBox(
                              width: 16,
                              height: 16,
                              radius: 8,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_isLoading ? 'Sending...' : 'Send'),
                  ),
                ),
              ],
            ),
          ),
          if (_responseText.isNotEmpty) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: SelectableText(
                _responseText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
