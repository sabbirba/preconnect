import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'app.dart';
import 'tools/ads_bridge.dart';
import 'tools/reward_support_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  await AdsBridge.initialize();
  await RewardSupportController.instance.load();
  final bootstrapState = await MyApp.bootstrap();
  runApp(MyApp(bootstrapState: bootstrapState));
}
