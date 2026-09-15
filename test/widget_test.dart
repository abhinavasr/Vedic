import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const MainApp());
    expect(find.text('Hello World!'), findsOneWidget);
  });
}
