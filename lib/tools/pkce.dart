import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String generatePkceVerifier({int length = 64}) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}

String codeChallengeS256(String verifier) {
  final bytes = sha256.convert(utf8.encode(verifier)).bytes;
  return base64UrlEncode(bytes).replaceAll('=', '');
}
