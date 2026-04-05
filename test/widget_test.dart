import 'package:flutter_test/flutter_test.dart';
import 'package:travel_trace/main.dart';
import 'package:travel_trace/pages/splash_page.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TravelTraceApp());
    expect(find.byType(TravelTraceApp), findsOneWidget);
    expect(find.byType(SplashPage), findsOneWidget);

    // Advance past the splash screen timer to avoid pending timer error
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
