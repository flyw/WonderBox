import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonder_box/core/storage/preferences_provider.dart';
import 'package:wonder_box/main.dart';

void main() {
  testWidgets('WonderBox App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const WonderBoxApp(),
      ),
    );

    // Verify app title renders
    expect(find.text('WonderBox AI'), findsOneWidget);
  });
}
