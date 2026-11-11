import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preconnect/pages/ui_kit.dart';

ThemeData _compactTheme() {
  return ThemeData(
    visualDensity: VisualDensity.compact,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

void main() {
  testWidgets('filled and outlined action buttons share one height', (
    tester,
  ) async {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: _compactTheme(),
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: AppActionButton(
                  key: const Key('outlined'),
                  onPressed: () {},
                  label: 'Google SSO',
                  padding: padding,
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: AppActionButton(
                  key: const Key('filled'),
                  onPressed: () {},
                  outlined: false,
                  label: 'Continue',
                  padding: padding,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('filled'))).height,
      tester.getSize(find.byKey(const Key('outlined'))).height,
    );
  });
}
