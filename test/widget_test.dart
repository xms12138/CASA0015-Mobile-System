import 'package:flutter_test/flutter_test.dart';
import 'package:travel_trace/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TravelTraceApp());
    expect(find.byType(TravelTraceApp), findsOneWidget);
  });
}
