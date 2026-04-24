import 'package:flutter/material.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/tools/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.initialize();
  runApp(const MyApp());
}
