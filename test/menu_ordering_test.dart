import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:demoqr/main.dart';
import 'package:demoqr/service_pages.dart';
import 'package:demoqr/staff_portal.dart';
import 'package:demoqr/order_checkout.dart';

void main() {
  testWidgets(
    'Card quantity adds directly to bag, preserves table and disables sold-out dish',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oldClient = Api.client;
      final oldDishes = List<Dish>.from(dishes);
      addTearDown(() {
        Api.client = oldClient;
        dishes
          ..clear()
          ..addAll(oldDishes);
      });
      Api.client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/menu')
                ? {
                    'items': [
                      {
                        'id': 'berry',
                        'name': 'Berry bowl',
                        'category': 'Desserts',
                        'experience': 'Café',
                        'image': 'dessert',
                        'price': 1200,
                        'description': 'Berries and vanilla',
                        'allergens': 'Milk',
                        'vegetarian': 1,
                        'available': true,
                      },
                      {
                        'id': 'chicken',
                        'name': 'Sold out platter',
                        'category': 'Main Courses',
                        'experience': 'Restaurant',
                        'image': 'chicken',
                        'price': 1800,
                        'description': 'Chicken and fries',
                        'allergens': 'Wheat',
                        'vegetarian': 0,
                        'available': false,
                      },
                    ],
                  }
                : {'id': 'T03', 'name': 'Table 03'},
          ),
          200,
        ),
      );
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(SocialHouse));
      state.applyRoute('Table:T03');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('qty-berry')));
      await tester.tap(find.byKey(const ValueKey('qty-berry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('bag-berry')));
      await tester.tap(find.byKey(const ValueKey('bag-berry')));
      await tester.pumpAndSettle();
      expect(state.page, 'Menu');
      expect(state.tableId, 'T03');
      expect(state.orderPayload()['items'][0]['quantity'], 2);
      expect(find.text('Bag (2)'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('bag-chicken')),
      );
      expect(button.onPressed, isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Customer admin login uses staff authentication and reveals Manage menu',
    (tester) async {
      final oldClient = Api.client;
      Api.remember(null);
      Api.user = null;
      addTearDown(() {
        Api.client = oldClient;
        Api.remember(null);
        Api.user = null;
      });
      Api.client = MockClient((r) async {
        expect(r.url.path, '/api/staff/auth/login');
        expect(jsonDecode(r.body)['email'], 'admin@example.com');
        return http.Response(
          jsonEncode({
            'token': 'independent-session',
            'user': {'id': 'owner', 'name': 'Admin', 'role': 'owner'},
          }),
          200,
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StaffPortal())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Admin email'),
        'admin@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'test-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(Api.token, 'independent-session');
      expect(find.text('Manage menu'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Changed total refreshes checkout and waits for explicit confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oldClient = Api.client;
      addTearDown(() => Api.client = oldClient);
      int quoteCount = 0, submissions = 0;
      Map<String, dynamic> quote(int total) => {
        'table': {'id': 'T03', 'name': 'Table 03'},
        'items': [
          {
            'id': 'coffee',
            'name': 'Coffee',
            'quantity': 1,
            'unit_price': 450,
            'notes': '',
          },
        ],
        'subtotal': 450,
        'tax': total - 450,
        'total': total,
      };
      Api.client = MockClient((r) async {
        if (r.url.path.endsWith('/quote')) {
          quoteCount++;
          return http.Response(
            jsonEncode(quote(quoteCount == 1 ? 450 : 495)),
            200,
          );
        }
        submissions++;
        if (submissions == 1) {
          return http.Response(
            jsonEncode({
              'error': 'The total changed. Review the updated summary and confirm again.',
            }),
            409,
          );
        }
        expect(jsonDecode(r.body)['expected_total'], 495);
        return http.Response(
          jsonEncode({
            'order': {
              ...quote(495),
              'id': 'AW-CHECK',
              'status': 'new',
              'table_name': 'Table 03',
              'history': [],
            },
          }),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderCheckout(
                order: const {
                  'table_id': 'T03',
                  'items': [
                    {'id': 'coffee', 'quantity': 1},
                  ],
                },
                onOrdered: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('PLACE ORDER · \$4.50'));
      await tester.tap(find.text('PLACE ORDER · \$4.50'));
      await tester.pumpAndSettle();
      expect(submissions, 1);
      expect(quoteCount, 2);
      expect(find.text('PLACE ORDER · \$4.95'), findsOneWidget);
      expect(find.textContaining('confirm again'), findsOneWidget);
      await tester.ensureVisible(find.text('PLACE ORDER · \$4.95'));
      await tester.tap(find.text('PLACE ORDER · \$4.95'));
      await tester.pumpAndSettle();
      expect(submissions, 2);
      expect(find.text('AW-CHECK'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
