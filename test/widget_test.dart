import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wonder_box/main.dart';

void main() {
  testWidgets('WonderBox App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: WonderBoxApp(),
      ),
    );

    // Verify app title renders
    expect(find.text('WonderBox AI'), findsOneWidget);
  });
}
