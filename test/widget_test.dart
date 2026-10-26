import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:demoqr/main.dart';

void main() {
  testWidgets('Product quantities update bag and subtotal', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Berry & Vanilla Cream Pot'), findsWidgets);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(find.text('ADD TO BAG  ·  \$24.00'), findsOneWidget);
    await tester.tap(find.text('ADD TO BAG  ·  \$24.00'));
    await tester.pumpAndSettle();
    expect(find.text('Bag (2)'), findsOneWidget);
    await tester.tap(find.text('Bag (2)'));
    await tester.pumpAndSettle();
    expect(find.text('\$24.00 USD'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove one Berry & Vanilla Cream Pot'));
    await tester.pumpAndSettle();
    expect(find.text('\$12.00 USD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Menu search filters products', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'cappuccino');
    await tester.pumpAndSettle();
    expect(find.text('Signature Cappuccino'), findsOneWidget);
    expect(find.text('Salmon Nigiri'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mobile layout and navigation fit narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservations').last);
    await tester.pumpAndSettle();
    expect(find.text('A seat at our table.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
