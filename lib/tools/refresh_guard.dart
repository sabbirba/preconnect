import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/pages/ui_kit.dart';

Future<bool> ensureOnline(BuildContext context, {bool notify = true}) async {
  final online = await ApiClient().hasConnection();
  if (!online && notify && context.mounted) {
    showAppSnackBar(context, 'Offline. Showing cached data.');
  }
  return online;
}
