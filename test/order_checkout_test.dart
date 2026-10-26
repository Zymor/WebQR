import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:demoqr/order_checkout.dart';
import 'package:demoqr/service_pages.dart';

void main() {
  testWidgets(
    'Customer reviews Table 03, saves one order and sees staff status updates',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int submissions = 0, callbacks = 0;
      String status = 'new';
      final data = {
        'table': {'id': 'T03', 'name': 'Table 03'},
        'items': [
          {
            'id': 'chicken',
            'name': 'Crispy Chicken Platter',
            'quantity': 2,
            'unit_price': 1800,
            'notes': '',
          },
        ],
        'subtotal': 3600,
        'tax': 0,
        'total': 3600,
      };
      Api.client = MockClient((req) async {
        dynamic value;
        if (req.url.path.endsWith('/quote')) {
          value = data;
        } else if (req.method == 'POST') {
          submissions++;
          final body = jsonDecode(req.body);
          expect(body['table_id'], 'T03');
          expect(body['items'][0]['quantity'], 2);
          expect(
            (body['access_token'] as String).length,
            greaterThanOrEqualTo(32),
          );
          value = {
            'order': {
              ...data,
              'id': 'AW-TEST',
              'table_name': 'Table 03',
              'status': status,
              'history': [],
              'payment_status': 'unpaid',
            },
          };
        } else {
          expect(req.headers['x-order-token'], isNotEmpty);
          value = {
            'order': {
              ...data,
              'id': 'AW-TEST',
              'table_name': 'Table 03',
              'status': status,
              'history': [],
              'payment_status': 'unpaid',
            },
          };
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderCheckout(
                order: {
                  'table_id': 'T03',
                  'items': [
                    {'id': 'chicken', 'quantity': 2, 'unit_price': 1800},
                  ],
                },
                onOrdered: () => callbacks++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Table 03'), findsOneWidget);
      expect(find.text('Crispy Chicken Platter'), findsOneWidget);
      await tester.ensureVisible(find.text('PLACE ORDER · \$36.00'));
      await tester.tap(find.text('PLACE ORDER · \$36.00'));
      await tester.pumpAndSettle();
      expect(find.text('AW-TEST'), findsOneWidget);
      expect(find.text('Status: NEW'), findsOneWidget);
      expect(submissions, 1);
      expect(callbacks, 1);
      status = 'preparing';
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Status: PREPARING'), findsOneWidget);
      expect(
        find.text('Pay at the counter · Payment not yet collected'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
