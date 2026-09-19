import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Login page renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeSenseApp());
    await tester.pump();

    // Verify login page elements are present
    expect(find.text('SafeSense'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });
}
