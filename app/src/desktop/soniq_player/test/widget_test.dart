import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soniq_player/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Tytuł aplikacji (MaterialApp.title)
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Soniq');

    // Ekran startowy powinien mieć elementy nawigacji.
    expect(find.byType(Scaffold), findsWidgets);
  });
}
