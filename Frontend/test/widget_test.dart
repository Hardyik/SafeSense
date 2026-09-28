import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Welcome page renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeSenseApp());
    // SplashScreen hands off to WelcomePage after a 1.1s branded beat;
    // pumpAndSettle lets the hand-off and route transition finish.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Welcome page elements (guest-first entry — login is secondary).
    expect(find.text('SafeSense'), findsWidgets);
    expect(find.text('Continue — See hazards & shelters'), findsOneWidget);
    expect(find.text('Log in to report hazards'), findsOneWidget);
  });
}
