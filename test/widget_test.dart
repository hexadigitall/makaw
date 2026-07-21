import 'package:flutter_test/flutter_test.dart';

import 'package:makaw_mobile/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MakawApp());
    expect(find.text('Makaw Browser'), findsWidgets);
  });
}
