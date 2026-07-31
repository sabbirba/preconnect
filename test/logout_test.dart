import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/auth/application/auth_bridge.dart';
import 'package:preconnect/features/auth/application/session_cleanup.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'logout cleanup deletes every sensitive value and clears dependents',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await AppStorage.initialize();

      for (final entry in const {
        PreConnectStorageKeys.accessToken: 'access',
        PreConnectStorageKeys.refreshToken: 'refresh',
        PreConnectStorageKeys.idToken: 'id',
        'wifi_captive_password': 'wifi-secret',
      }.entries) {
        await TokenStorage.instance.write(key: entry.key, value: entry.value);
      }

      var cacheCleared = false;
      var uiCleared = false;
      await clearAuthenticationState(
        clearTransientCaches: () => cacheCleared = true,
        clearUiArtifacts: () async => uiCleared = true,
      );

      expect(cacheCleared, isTrue);
      expect(uiCleared, isTrue);
      for (final key in const [
        PreConnectStorageKeys.accessToken,
        PreConnectStorageKeys.refreshToken,
        PreConnectStorageKeys.idToken,
        'wifi_captive_password',
      ]) {
        expect(await TokenStorage.instance.read(key: key), isNull);
      }
    },
  );

  test('logout completion is delegated to the configured app shell', () async {
    var completionCount = 0;
    AuthUiBridge.configure(
      openLogoutView: (_) async => false,
      clearLoginArtifacts: () async {},
      clearPrinterArtifacts: () async {},
      completeLogout: () async {
        completionCount++;
      },
    );

    await AuthUiBridge.completeLogout();

    expect(completionCount, 1);
  });

  testWidgets(
    'logout dialog keeps a stable progress state until cleanup finishes',
    (tester) async {
      final cleanup = Completer<void>();
      bool? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  confirmed = await showBracuConfirmationWithActionDialog(
                    context,
                    icon: Icons.logout,
                    title: 'Confirm Sign Out?',
                    message: 'Clear stored data.',
                    confirmLabel: 'Sign Out',
                    onConfirm: () => cleanup.future,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel'),
            )
            .onPressed,
        isNull,
      );

      cleanup.complete();
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(confirmed, isTrue);
    },
  );
}
