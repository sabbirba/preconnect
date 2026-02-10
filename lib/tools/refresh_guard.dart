import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/pages/ui_kit.dart';

Future<bool> ensureOnline(BuildContext context, {bool notify = true}) async {
  final online = await BracuAuthManager().hasConnection();
  if (!online && notify && context.mounted) {
    showAppSnackBar(context, 'Offline. Showing cached data.');
  }
  return online;
}
