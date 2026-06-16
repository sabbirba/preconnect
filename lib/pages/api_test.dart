import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh.dart';
import 'package:preconnect/tools/token_storage.dart';

class ApiTestPage extends StatefulWidget {
  const ApiTestPage({super.key});

  @override
  State<ApiTestPage> createState() => _ApiTestPageState();
}

class _ApiTestPageState extends State<ApiTestPage> {
  final TextEditingController _urlController = TextEditingController(
    text: '${ApiConfig.connectApiBase}/adp/v1/staffs/7487',
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
  String? _accessToken;
  String? _refreshToken;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadTokens());
  }

  Future<void> _loadTokens() async {
    final accessToken = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.accessToken,
    );
    final refreshToken = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.refreshToken,
    );
    if (!mounted) return;
    setState(() {
      _accessToken = accessToken?.trim().isEmpty == true ? null : accessToken;
      _refreshToken = refreshToken?.trim().isEmpty == true
          ? null
          : refreshToken;
    });
  }

  Future<void> _sendRequest() async {
    if (_isLoading) return;
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final startedAt = DateTime.now();
    final method = _method;

    try {
      var accessToken = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.accessToken,
      );
      if (accessToken == null || accessToken.isEmpty) {
        return;
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
            key: PreConnectStorageKeys.accessToken,
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
      await _loadTokens();
      setState(() {
        _responseText = prettyBody.isEmpty
            ? '${response.statusCode} ${response.reasonPhrase ?? ''} • ${tookMs}ms'
            : prettyBody;
      });
    } catch (_) {
      return;
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
      ...compressionHeadersForUri(uri),
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

  _JwtSnapshot _snapshotJwt(String? token) {
    final raw = token?.trim() ?? '';
    if (raw.isEmpty) return const _JwtSnapshot();

    final parts = raw.split('.');
    if (parts.length != 3) return const _JwtSnapshot();

    try {
      final payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return const _JwtSnapshot();

      final claims = decoded.cast<String, dynamic>();
      final expSeconds = int.tryParse('${claims['exp'] ?? ''}');
      final expiry = expSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000);
      return _JwtSnapshot(expiry: expiry, claims: claims);
    } catch (_) {
      return const _JwtSnapshot();
    }
  }

  String _formatClaims(Map<String, dynamic>? claims) {
    if (claims == null || claims.isEmpty) return '';
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(claims);
  }

  Widget _buildAccessTokenSnapshot(BuildContext context) {
    final snapshot = _snapshotJwt(_accessToken);
    final claims = _formatClaims(snapshot.claims);
    if (claims.isEmpty) return const SizedBox.shrink();

    return _TokenField(label: 'Access Token Details', value: claims);
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Connect API Test',
      subtitle: 'BRACU SSO Auth Session',
      icon: Icons.science_outlined,
      body: BracuRefreshList(
        onRefresh: _sendRequest,
        children: [
          _buildAccessTokenSnapshot(context),
          const SizedBox(height: 12),
          _TokenField(label: 'Access Token', value: _accessToken),
          const SizedBox(height: 12),
          _TokenField(label: 'Refresh Token', value: _refreshToken),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _methods
                .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
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
            decoration: InputDecoration(
              hintText: '${ApiConfig.connectApiBase}/adp/v1/staffs/7487',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: BracuActionButton(
              onPressed: _isLoading ? null : _sendRequest,
              icon: Icons.play_arrow_rounded,
              label: 'Send',
              isLoading: _isLoading,
            ),
          ),
          const SizedBox(height: 20),
          if (_responseText.isNotEmpty)
            SelectableText(
              _responseText,
              style: TextStyle(
                fontSize: 12,
                color: BracuPalette.textPrimary(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _JwtSnapshot {
  const _JwtSnapshot({this.expiry, this.claims});

  final DateTime? expiry;
  final Map<String, dynamic>? claims;
}

class _TokenField extends StatelessWidget {
  const _TokenField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textSecondary(context),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: BracuPalette.textSecondary(
                context,
              ).withValues(alpha: 0.22),
            ),
            color: BracuPalette.card(context).withValues(alpha: 0.35),
          ),
          child: SelectableText(
            displayValue,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: BracuPalette.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }
}
