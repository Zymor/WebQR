import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:demoqr/menu_management.dart';

void main() {
  testWidgets(
    'Add with photo, edit, archive and restore work on desktop and mobile',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = <Map<String, dynamic>>[];
      int uploads = 0;
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? data,
      }) async {
        if (path == '/staff/media') {
          uploads++;
          expect(data!['mime'], 'image/jpeg');
          expect(data['base64'], isNotEmpty);
          return {'image': '/api/media/test'};
        }
        if (method == 'GET') {
          return {
            'items': items.map((m) => Map<String, dynamic>.from(m)).toList(),
            'categories': [
              {
                'id': 'mains',
                'name': 'Main Courses',
                'experience': 'Restaurant',
              },
            ],
          };
        }
        if (path.endsWith('/archive')) {
          items[0]['archived'] = data!['archived'];
          return {'message': 'Saved'};
        }
        expect(data!['image'], '/api/media/test');
        final dish = {
          ...data,
          'id': 'new-dish',
          'category': 'Main Courses',
          'image': 'chicken',
          'archived': false,
        };
        if (method == 'POST') {
          items.add(dish);
        } else {
          items[0] = dish;
        }
        return {'message': 'Saved'};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MenuManagement(
                request: request,
                apiBase: '/api',
                canManage: true,
                photoPicker: () async => {
                  'bytes': File('assets/images/chicken.jpg').readAsBytesSync(),
                  'mime': 'image/jpeg',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add dish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload photo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dish name'),
        'Garden bowl',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Courses · Restaurant').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price in USD'),
        '12.50',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Description'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Fresh vegetables and rice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ingredients'),
        'Rice, vegetables',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Allergens'),
        'Soy',
      );
      await tester.tap(find.text('Save dish'));
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(items.single['price'], 1250);
      expect(items.single['ingredients'], 'Rice, vegetables');
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Garden bowl'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit Garden bowl'));
      await tester.pumpAndSettle();
      // Replace the existing photo as well as the name.
      await tester.tap(find.text('Replace photo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dish name'),
        'Updated bowl',
      );
      await tester.tap(find.text('Save dish'));
      await tester.pumpAndSettle();
      expect(uploads, 2);
      await tester.tap(find.byTooltip('Remove Updated bowl'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Updated bowl?'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(items.single['archived'], true);
      await tester.tap(find.byTooltip('Restore Updated bowl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();
      expect(items.single['archived'], false);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Updated bowl'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Read-only staff cannot see menu mutation controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuManagement(
            request: (
              String path, {
              String method = 'GET',
              Map<String, dynamic>? data,
            }) async => {'items': [], 'categories': []},
            apiBase: '/api',
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add dish'), findsNothing);
  });
}
