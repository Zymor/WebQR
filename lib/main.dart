import 'package:flutter/material.dart';

import 'service_pages.dart';
import 'explore_pages.dart';
import 'tables_page.dart';
import 'order_checkout.dart';
import 'staff_portal.dart';

import 'dart:convert';
import 'dart:async';

import 'local_store.dart' if (dart.library.js_interop) 'local_store_web.dart';

const ivory = Color(0xFFF5F3ED);
const ink = Color(0xFF17233F);
const brandBlue = Color(0xFF0A38A8);
const rust = Color(0xFFB65C32);
const muted = Color(0xFF797B70);
void main() => runApp(const MyApp());

class Dish {
  final String id, name, category, experience, image, description, allergens;
  final double price;
  final bool vegetarian;
  const Dish(
    this.id,
    this.name,
    this.category,
    this.experience,
    this.image,
    this.price,
    this.description,
    this.allergens, {
    this.vegetarian = false,
  });
}

final List<Dish> dishes = [
  Dish(
    'berry',
    'Berry & Vanilla Cream Pot',
    'Desserts',
    'Café',
    'dessert',
    12,
    'Silky vanilla cream meets bright seasonal berries in a little pot of happiness. Fresh, gently sweet, and made for one more spoonful.',
    'Milk, eggs',
    vegetarian: true,
  ),
  Dish(
    'sandwich',
    'The Golden Grilled Cheese',
    'Breakfast',
    'Café',
    'sandwich',
    14,
    'Golden sourdough, a generous blend of melted cheddar and mozzarella, and a little comfort in every bite.',
    'Wheat, milk',
    vegetarian: true,
  ),
  Dish(
    'chicken',
    'Crispy Chicken Platter',
    'Main Courses',
    'Restaurant',
    'chicken',
    18,
    'Crispy golden chicken, seasoned fries and our house-made creamy herb dip. A feel-good favorite.',
    'Wheat, eggs, milk',
  ),
  Dish(
    'sushi',
    'Salmon Nigiri',
    'Seafood',
    'Restaurant',
    'sushi',
    22,
    'Beautifully cut salmon over delicately seasoned sushi rice, with pickled ginger and wasabi.',
    'Fish, soy',
  ),
  Dish(
    'coffee',
    'Signature Cappuccino',
    'Hot Coffee',
    'Café',
    'coffee',
    4.5,
    'Our house espresso with silky steamed milk. Rich, balanced, and made for slow mornings.',
    'Milk',
    vegetarian: true,
  ),
  Dish(
    'dinner',
    'Chef’s Tasting Experience',
    'Set Meals',
    'Restaurant',
    'restaurant',
    48,
    'A seasonal journey through the kitchen, thoughtfully plated and made for memorable evenings.',
    'Ask our team for the seasonal allergen list',
  ),
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'After Work — A little something for every moment',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ivory,
      fontFamily: 'SocialSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandBlue,
        primary: brandBlue,
        surface: ivory,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 15, height: 1.65),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFECE9E1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 23),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
    onGenerateInitialRoutes: (route) => [
      MaterialPageRoute<void>(
        settings: RouteSettings(name: route),
        builder: (_) => const SocialHouse(),
      ),
    ],
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const SocialHouse(),
    ),
  );
}

class SocialHouse extends StatefulWidget {
  const SocialHouse({super.key});
  @override
  State<SocialHouse> createState() => _SocialHouseState();
}

class _SocialHouseState extends State<SocialHouse> {
  String? tableId, tableName;
  String page = 'Details', category = 'All', search = '', experience = 'All';
  Dish selected = dishes.first;
  int quantity = 1;
  bool vegetarian = false;
  double maxPrice = 60;
  StreamSubscription<String>? routeSubscription;
  final Set<String> favorites = {};
  final Map<String, int> cart = {};
  final Map<String, String> itemNotes = {};
  final ScrollController scroll = ScrollController();
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  double get subtotal => cart.entries.fold(
    0,
    (a, e) =>
        a +
        dishes
            .where((d) => d.id == e.key)
            .fold<double>(0, (a, d) => a + d.price * e.value),
  );
  @override
  void initState() {
    super.initState();
    applyRoute(readRoute());
    routeSubscription = routeChanges.listen((route) {
      if (mounted) {
        setState(() => applyRoute(route));
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    });
    try {
      final savedTable = readLocal('social.table');
      if (tableId == null && savedTable != null && savedTable.isNotEmpty) {
        final stored = jsonDecode(savedTable);
        tableId = stored['id'];
        tableName = stored['name'];
      }
      final rawNotes = readLocal('afterwork.item_notes');
      if (rawNotes != null) {
        itemNotes.addAll(Map<String, String>.from(jsonDecode(rawNotes)));
      }
      final savedCart = readLocal('social.cart');
      if (savedCart != null) {
        cart.addAll(Map<String, int>.from(jsonDecode(savedCart)));
      }
      final savedFavorites = readLocal('social.favorites');
      if (savedFavorites != null) {
        favorites.addAll(List<String>.from(jsonDecode(savedFavorites)));
      }
    } catch (_) {
      /* Ignore invalid browser-local data. */
    }
    refreshMenu();
  }

  Future<void> refreshMenu() async {
    try {
      final response = await Api.request('/menu');
      final items = (response['items'] as List)
          .map(
            (d) => Dish(
              d['id'],
              d['name'],
              d['category'],
              d['experience'],
              d['image'],
              d['price'] / 100.0,
              d['description'],
              d['allergens'],
              vegetarian: d['vegetarian'] == 1,
            ),
          )
          .toList();
      if (mounted) {
        setState(() {
          dishes.clear();
          dishes.addAll(items);
          cart.removeWhere((id, _) => !items.any((d) => d.id == id));
          if (items.any((d) => d.id == selected.id)) {
            selected = items.firstWhere((d) => d.id == selected.id);
          }
        });
      }
    } catch (_) {
      /* Offline sample menu remains explicitly labelled. */
    }
  }

  void applyRoute(String route) {
    final parts = route.split(':');
    if (parts.first == 'Table' && parts.length == 2) {
      page = 'Menu';
      tableId = parts[1];
      tableName = parts[1];
      Api.request('/tables/${Uri.encodeComponent(parts[1])}')
          .then((value) {
            if (mounted && tableId == parts[1]) {
              setState(() {
                tableName = value['name'];
              });
            }
          })
          .catchError((Object error) {
            if (mounted) {
              setState(() {
                tableId = null;
                tableName = null;
              });
              notify(error.toString());
            }
          });
      return;
    }
    const routes = [
      'Tables',
      'Home',
      'Details',
      'Menu',
      'Favorites',
      'Cart',
      'Reservations',
      'Account',
      'Checkout',
      'Admin',
      'Café',
      'Restaurant',
      'Pub & Lounge',
      'Events',
      'Gallery',
      'Contact',
      'Newsletter',
      'About',
      'Privacy & Terms',
    ];
    if (route.isEmpty) return;
    page = routes.contains(parts.first) ? parts.first : 'Not found';
    if (page == 'Details' &&
        parts.length > 1 &&
        dishes.any((d) => d.id == parts[1])) {
      selected = dishes.firstWhere((d) => d.id == parts[1]);
    }
  }

  Map<String, dynamic> orderPayload() => {
    'table_id': tableId,
    'items': cart.entries
        .map(
          (e) => {
            'id': e.key,
            'quantity': e.value,
            'unit_price': (dishes.firstWhere((d) => d.id == e.key).price * 100)
                .round(),
            'notes': itemNotes[e.key] ?? '',
          },
        )
        .toList(),
  };
  void saveLocal() {
    writeLocal(
      'social.table',
      tableId == null ? '' : jsonEncode({'id': tableId, 'name': tableName}),
    );
    writeLocal('social.cart', jsonEncode(cart));
    writeLocal('afterwork.item_notes', jsonEncode(itemNotes));
    writeLocal('social.favorites', jsonEncode(favorites.toList()));
  }

  Future<void> toggleFavorite(String id) async {
    final saved = !favorites.contains(id);
    if (Api.token != null) {
      try {
        await Api.request(
          '/favorites',
          method: 'POST',
          data: {'id': id, 'saved': saved},
        );
      } catch (e) {
        notify(e.toString());
        return;
      }
    }
    setState(() {
      if (saved) {
        favorites.add(id);
      } else {
        favorites.remove(id);
      }
    });
    saveLocal();
  }

  void go(String value) {
    setState(() {
      page = value;
      search = '';
    });
    saveLocal();
    writeRoute(value == 'Details' ? 'Details:${selected.id}' : value);
    if (Api.token != null && value == 'Favorites') {
      Api.request('/me')
          .then((v) {
            if (mounted) {
              setState(() {
                favorites.clear();
                favorites.addAll(List<String>.from(v['favorites']));
              });
            }
          })
          .catchError((Object _) {});
    }
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void open(Dish dish) {
    setState(() {
      selected = dish;
      quantity = 1;
    });
    go('Details');
  }

  void notify(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width > 550 ? 420 : null,
    ),
  );
  void add() {
    setState(
      () => cart.update(
        selected.id,
        (n) => n + quantity,
        ifAbsent: () => quantity,
      ),
    );
    saveLocal();
    notify('$quantity × ${selected.name} added to your bag');
  }

  @override
  void dispose() {
    routeSubscription?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 760;
      return Scaffold(
        body: Column(
          children: [
            Container(
              color: brandBlue,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'GOOD FOOD. GREAT COMPANY. YOUR KIND OF PLACE.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2.6,
                  color: Color(0xFFE5DAC5),
                ),
              ),
            ),
            header(constraints.maxWidth < 1150),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: mobile ? 22 : 64,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: switch (page) {
                            'Details' => details(mobile),
                            'Tables' => const TablesPage(),
                            'Menu' || 'Favorites' => menu(mobile),
                            'Cart' => cartPage(mobile),
                            'Admin' => const StaffPortal(),
                            'Checkout' || 'Account' => OrderCheckout(
                              key: const ValueKey('checkout'),
                              order: orderPayload(),
                              onOrdered: () {
                                setState(() => cart.clear());
                                saveLocal();
                              },
                            ),
                            'Reservations' => ServicePage(
                              key: ValueKey(page),
                              page: page,
                              onMenuChanged: refreshMenu,
                              order: {
                                'table_id': tableId,
                                'items': cart.entries
                                    .map(
                                      (e) => {
                                        'id': e.key,
                                        'quantity': e.value,
                                        'unit_price':
                                            (dishes
                                                        .firstWhere(
                                                          (d) => d.id == e.key,
                                                        )
                                                        .price *
                                                    100)
                                                .round(),
                                      },
                                    )
                                    .toList(),
                              },
                              onOrdered: () {
                                setState(() => cart.clear());
                                saveLocal();
                              },
                            ),
                            'Events' ||
                            'Gallery' ||
                            'Contact' ||
                            'Newsletter' => ExplorePage(
                              key: ValueKey(page),
                              page: page,
                            ),
                            'Home' => home(mobile),
                            'Café' ||
                            'Restaurant' ||
                            'Pub & Lounge' => experiencePage(mobile),
                            _ => information(mobile),
                          },
                        ),
                      ),
                    ),
                    footer(mobile),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget header(bool mobile) => Container(
    padding: EdgeInsets.symmetric(horizontal: mobile ? 20 : 64, vertical: 24),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE1DED5))),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => go('Home'),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/images/after-work-logo.png',
                  width: mobile ? 112 : 140,
                  height: mobile ? 56 : 70,
                  fit: BoxFit.cover,
                  semanticLabel: 'After Work — home',
                ),
              ),
            ),
          ),
        ),
        if (!mobile)
          ...['Home', 'Our spaces', 'Menu', 'Tables'].map(
            (s) => Padding(
              padding: const EdgeInsets.only(right: 29),
              child: TextButton(
                onPressed: () => go(
                  s == 'Our spaces'
                      ? 'Café'
                      : s == 'Our story'
                      ? 'About'
                      : s,
                ),
                child: Text(
                  s,
                  style: TextStyle(fontSize: 13, color: page == s ? rust : ink),
                ),
              ),
            ),
          ),
        if (!mobile)
          IconButton(
            tooltip: 'Favorites',
            onPressed: () => go('Favorites'),
            icon: const Icon(Icons.favorite_border, size: 19),
          ),
        TextButton(
          onPressed: () => go('Cart'),
          child: Text('Bag ($cartCount)', style: const TextStyle(fontSize: 12)),
        ),
        if (!mobile) ...[
          const SizedBox(width: 15),
          FilledButton(
            onPressed: () => go('Reservations'),
            child: const Text(
              'RESERVE A TABLE  ↗',
              style: TextStyle(fontSize: 10, letterSpacing: 1),
            ),
          ),
        ],
        if (mobile)
          PopupMenuButton<String>(
            tooltip: 'Navigation',
            onSelected: go,
            itemBuilder: (_) => [
              'Home',
              'Menu',
              'Tables',
              'Café',
              'Restaurant',
              'Pub & Lounge',
              'Reservations',
              'Gallery',
              'Events',
              'Account',
              'Admin',
              'Favorites',
              'About',
              'Contact',
            ].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
          ),
      ],
    ),
  );
  Widget label(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: rust,
      fontSize: 10,
      letterSpacing: 1,
      fontWeight: FontWeight.w600,
    ),
  );
  Widget photo(
    String name, {
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: Image.asset(
      'assets/images/$name.jpg',
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, error, stack) => Container(
        height: height,
        width: width,
        color: const Color(0xFFE3DED1),
        child: const Center(
          child: Icon(Icons.restaurant, color: rust, size: 40),
        ),
      ),
    ),
  );
  Widget title(String text, {double size = 48}) => Text(
    text,
    style: TextStyle(
      fontFamily: 'SocialSerif',
      fontSize: size,
      height: 1.05,
      letterSpacing: -1.7,
      color: ink,
    ),
  );
  Widget details(bool mobile) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 32),
        child: Wrap(
          spacing: 9,
          children: [
            InkWell(
              onTap: () => go('Home'),
              child: const Text(
                'Home',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ),
            const Text('/', style: TextStyle(fontSize: 10, color: muted)),
            InkWell(
              onTap: () => go('Menu'),
              child: const Text(
                'Our menu',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ),
            const Text('/', style: TextStyle(fontSize: 10, color: muted)),
            Text(selected.name, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
      if (mobile) ...[
        productImage(420),
        const SizedBox(height: 30),
        productInfo(true),
      ] else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 43, child: productInfo(false)),
            const SizedBox(width: 70),
            Expanded(flex: 57, child: productImage(650)),
          ],
        ),
      const SizedBox(height: 38),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final item in [
            (Icons.eco_outlined, 'Thoughtfully sourced'),
            (Icons.restaurant_outlined, 'Made fresh, always'),
            (Icons.favorite_border, 'A little love in every bite'),
          ])
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: mobile ? 8 : 35,
                  vertical: 20,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.$1, size: 17, color: rust),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.$2,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Divider(color: Color(0xFFDCD8CF)),
      ),
      const SizedBox(height: 23),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('More to fall in love with'),
                const SizedBox(height: 15),
                title('Good taste runs in the family.', size: mobile ? 34 : 44),
              ],
            ),
          ),
          if (!mobile)
            TextButton(
              onPressed: () => go('Menu'),
              child: const Text(
                'EXPLORE THE MENU  ↗',
                style: TextStyle(fontSize: 10, letterSpacing: 1),
              ),
            ),
        ],
      ),
      const SizedBox(height: 30),
      dishGrid(
        dishes.where((d) => d.id != selected.id).take(3).toList(),
        mobile,
      ),
      const SizedBox(height: 70),
    ],
  );
  Widget productImage(double height) => Stack(
    children: [
      photo(selected.image, height: height, width: double.infinity),
      Positioned(
        top: 19,
        left: 19,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: ivory,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            'HOUSE FAVORITE',
            style: TextStyle(fontSize: 9, letterSpacing: 1.5),
          ),
        ),
      ),
      Positioned(
        top: 15,
        right: 15,
        child: IconButton.filledTonal(
          style: IconButton.styleFrom(backgroundColor: ivory),
          tooltip: 'Save to favorites',
          onPressed: () => toggleFavorite(selected.id),
          icon: Icon(
            favorites.contains(selected.id)
                ? Icons.favorite
                : Icons.favorite_border,
            color: ink,
            size: 20,
          ),
        ),
      ),
      Positioned(
        bottom: 20,
        left: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: ivory.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Freshly made. Beautifully simple.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ),
    ],
  );
  Widget productInfo(bool mobile) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 6),
      label('${selected.experience}  /  ${selected.category}'),
      const SizedBox(height: 21),
      title(selected.name, size: mobile ? 49 : 62),
      const SizedBox(height: 19),
      Row(
        children: [
          Text(
            '\$${selected.price.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 26, letterSpacing: -1),
          ),
          const SizedBox(width: 8),
          const Text('USD', style: TextStyle(fontSize: 10, color: muted)),
          const Spacer(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE7EDFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '●  Made to order',
                style: TextStyle(fontSize: 10, color: ink),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 26),
      Text(
        selected.description,
        style: const TextStyle(
          fontSize: 14,
          height: 1.9,
          color: Color(0xFF64685E),
        ),
      ),
      const SizedBox(height: 28),
      if (selected.vegetarian) ...[
        const Row(
          children: [
            Icon(Icons.eco_outlined, size: 17, color: ink),
            SizedBox(width: 7),
            Text('Vegetarian', style: TextStyle(fontSize: 11)),
          ],
        ),
        const SizedBox(height: 17),
      ],
      infoRow('Allergen information', selected.allergens),
      infoRow('Prepared', 'Fresh in our kitchen'),
      const SizedBox(height: 23),
      const Text(
        'MAKE IT YOUR MOMENT',
        style: TextStyle(fontSize: 9, letterSpacing: 1.8, color: muted),
      ),
      const SizedBox(height: 11),
      Row(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD5D3C8)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Decrease quantity',
                  onPressed: quantity > 1
                      ? () => setState(() => quantity--)
                      : null,
                  icon: const Icon(Icons.remove, size: 16),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '$quantity'.padLeft(2, '0'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Increase quantity',
                  onPressed: quantity < 20
                      ? () => setState(() => quantity++)
                      : null,
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rust),
              onPressed: add,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 16),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'ADD TO BAG  ·  \$${(selected.price * quantity).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 10, letterSpacing: .8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text(
        'Made fresh • Order for your table • Pay at the counter',
        style: TextStyle(fontSize: 10, color: muted),
      ),
      const SizedBox(height: 23),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: const Color(0xFFDBD8CF)),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'The little details',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Our sample menu celebrates seasonal ingredients. Please discuss allergies with the team before ordering. Images are serving inspiration; presentation may vary.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget infoRow(String left, String right) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDFDBD2))),
    ),
    child: Row(
      children: [
        Text(left, style: const TextStyle(fontSize: 11, color: muted)),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            right,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
  Widget dishGrid(List<Dish> list, bool mobile) => LayoutBuilder(
    builder: (_, c) {
      final columns = c.maxWidth < 600
          ? 1
          : c.maxWidth < 950
          ? 2
          : 3;
      return Wrap(
        spacing: 22,
        runSpacing: 25,
        children: list
            .map(
              (dish) => SizedBox(
                width: (c.maxWidth - (columns - 1) * 22) / columns,
                child: dishCard(dish),
              ),
            )
            .toList(),
      );
    },
  );
  Widget dishCard(Dish dish) => InkWell(
    onTap: () => open(dish),
    borderRadius: BorderRadius.circular(9),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECE9E1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label(dish.category)),
              IconButton(
                tooltip: 'Favorite ${dish.name}',
                onPressed: () => toggleFavorite(dish.id),
                icon: Icon(
                  favorites.contains(dish.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 17,
                  color: ink,
                ),
              ),
            ],
          ),
          Text(
            dish.name,
            style: const TextStyle(
              fontFamily: 'SocialSerif',
              fontSize: 27,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 17),
          Stack(
            children: [
              photo(dish.image, height: 270, width: double.infinity),
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: ivory,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '\$${dish.price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            dish.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.65,
              color: Color(0xFF65695E),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Text(
                'DISCOVER YOUR NEXT FAVORITE',
                style: TextStyle(fontSize: 8, letterSpacing: 1.2),
              ),
              Spacer(),
              Icon(Icons.arrow_outward, size: 17),
            ],
          ),
        ],
      ),
    ),
  );
  Widget menu(bool mobile) {
    final list = dishes
        .where(
          (d) =>
              (page != 'Favorites' || favorites.contains(d.id)) &&
              (category == 'All' || d.category == category) &&
              (experience == 'All' || d.experience == experience) &&
              (!vegetarian || d.vegetarian) &&
              d.price <= maxPrice &&
              '${d.name} ${d.description}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tableId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE7EDFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.table_restaurant_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Welcome to After Work · $tableName',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        tableId = null;
                        tableName = null;
                      });
                      saveLocal();
                      writeRoute('Menu');
                    },
                    child: const Text('Clear table'),
                  ),
                ],
              ),
            ),
          label('Made for the moments in between'),
          const SizedBox(height: 15),
          title(
            page == 'Favorites'
                ? 'Your kind of favorites.'
                : 'Something for every craving.',
            size: mobile ? 43 : 64,
          ),
          const SizedBox(height: 20),
          const Text(
            'From slow mornings to one-more-bite evenings. Explore our sample menu.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 30),
          TextField(
            onChanged: (s) => setState(() => search = s),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Find your next favorite…',
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['All', ...dishes.map((d) => d.category).toSet()]
                .map(
                  (s) => ChoiceChip(
                    label: Text(s),
                    selected: category == s,
                    onSelected: (_) => setState(() => category = s),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: experience,
                items: ['All', 'Café', 'Restaurant', 'Pub & Lounge']
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s == 'All' ? 'All experiences' : s),
                      ),
                    )
                    .toList(),
                onChanged: (s) => setState(() => experience = s!),
              ),
              FilterChip(
                label: const Text('Vegetarian'),
                selected: vegetarian,
                onSelected: (b) => setState(() => vegetarian = b),
              ),
              SizedBox(
                width: 230,
                child: Row(
                  children: [
                    Text(
                      'Up to \$${maxPrice.round()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: maxPrice,
                        min: 5,
                        max: 60,
                        divisions: 11,
                        onChanged: (v) => setState(() => maxPrice = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(60),
              child: Column(
                children: [
                  const Icon(Icons.restaurant_menu, size: 40, color: rust),
                  const SizedBox(height: 15),
                  const Text(
                    'No dishes here yet. Try another filter or save a favorite.',
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        category = 'All';
                        experience = 'All';
                        vegetarian = false;
                        maxPrice = 60;
                      });
                      go('Menu');
                    },
                    child: const Text('Explore all dishes'),
                  ),
                ],
              ),
            )
          else
            dishGrid(list, mobile),
        ],
      ),
    );
  }

  Widget home(bool mobile) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 35),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            photo(
              'restaurant',
              height: mobile ? 540 : 650,
              width: double.infinity,
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(
                    colors: [Color(0xCC10221C), Color(0x3310221C)],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
              ),
            ),
            Positioned(
              left: mobile ? 25 : 60,
              bottom: 55,
              right: 25,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WELCOME TO AFTER WORK',
                    style: TextStyle(
                      color: Color(0xFFE3C59D),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Three experiences.\nOne destination.',
                    style: TextStyle(
                      fontFamily: 'SocialSerif',
                      color: ivory,
                      fontSize: mobile ? 55 : 88,
                      height: 1.02,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Coffee by day. Dining by evening. Moments all night.',
                    style: TextStyle(color: ivory, fontSize: 14),
                  ),
                  const SizedBox(height: 30),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ivory,
                          foregroundColor: ink,
                        ),
                        onPressed: () => go('Menu'),
                        child: const Text('EXPLORE OUR MENU  ↗'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: rust),
                        onPressed: () => go('Reservations'),
                        child: const Text('RESERVE A TABLE'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 65),
        label('Find your place'),
        const SizedBox(height: 15),
        title('However your day unfolds.'),
        const SizedBox(height: 30),
        LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 20,
            runSpacing: 20,
            children: ['Café', 'Restaurant', 'Pub & Lounge']
                .map(
                  (s) => SizedBox(
                    width: mobile ? c.maxWidth : (c.maxWidth - 40) / 3,
                    child: InkWell(
                      onTap: () => go(s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          photo(
                            s == 'Café' ? 'coffee' : 'restaurant',
                            height: 280,
                            width: double.infinity,
                          ),
                          const SizedBox(height: 15),
                          title('$s ↗', size: 34),
                          const SizedBox(height: 10),
                          Text(
                            s == 'Café'
                                ? 'Start your day beautifully.'
                                : s == 'Restaurant'
                                ? 'Every meal deserves a moment.'
                                : 'Where great evenings begin.',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 70),
        label('From our kitchen'),
        const SizedBox(height: 15),
        title('Meet the house favorites.'),
        const SizedBox(height: 30),
        dishGrid(dishes.take(3).toList(), mobile),
        const SizedBox(height: 60),
      ],
    ),
  );
  Widget experiencePage(bool mobile) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          children: ['Café', 'Restaurant', 'Pub & Lounge']
              .map(
                (s) => ChoiceChip(
                  label: Text(s),
                  selected: page == s,
                  onSelected: (_) => go(s),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 30),
        label('After Work / $page'),
        const SizedBox(height: 20),
        title(
          page == 'Café'
              ? 'Slow mornings.\nBeautiful beginnings.'
              : page == 'Restaurant'
              ? 'Every meal\ndeserves a moment.'
              : 'Stay a little longer.',
          size: mobile ? 48 : 76,
        ),
        const SizedBox(height: 25),
        photo(
          page == 'Café' ? 'coffee' : 'restaurant',
          height: 440,
          width: double.infinity,
        ),
        const SizedBox(height: 25),
        const Text(
          'Thoughtful ingredients. Warm spaces. Good company. Find your favorite corner at After Work.',
        ),
        const SizedBox(height: 25),
        FilledButton(
          onPressed: () {
            setState(() {
              experience = page == 'Pub & Lounge' ? 'All' : page;
              category = 'All';
            });
            go('Menu');
          },
          child: const Text('DISCOVER THE MENU  ↗'),
        ),
        const SizedBox(height: 50),
      ],
    ),
  );
  Widget cartPage(bool mobile) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('A little happiness to go'),
        const SizedBox(height: 15),
        title('Your bag.'),
        const SizedBox(height: 30),
        if (cart.isEmpty) ...[
          const Text('Your next favorite is waiting on the menu.'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => go('Menu'),
            child: const Text('EXPLORE THE MENU'),
          ),
        ] else ...[
          ...cart.entries.map((e) {
            final d = dishes.firstWhere((d) => d.id == e.key);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  photo(d.image, height: 80, width: 80),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name),
                        TextFormField(
                          key: ValueKey('note-${d.id}'),
                          initialValue: itemNotes[d.id] ?? '',
                          maxLength: 300,
                          decoration: const InputDecoration(
                            hintText: 'Item notes (optional)',
                            counterText: '',
                          ),
                          style: const TextStyle(fontSize: 11),
                          onChanged: (v) {
                            itemNotes[d.id] = v;
                            saveLocal();
                          },
                        ),
                        Text(
                          '\$${d.price.toStringAsFixed(2)} each',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove one ${d.name}',
                    onPressed: () => setState(() {
                      if (e.value == 1) {
                        cart.remove(e.key);
                      } else {
                        cart[e.key] = e.value - 1;
                      }
                    }),
                    icon: const Icon(Icons.remove, size: 16),
                  ),
                  Text('${e.value}'),
                  IconButton(
                    tooltip: 'Add one ${d.name}',
                    onPressed: () => setState(() => cart[e.key] = e.value + 1),
                    icon: const Icon(Icons.add, size: 16),
                  ),
                  if (!mobile)
                    Text('\$${(d.price * e.value).toStringAsFixed(2)}'),
                ],
              ),
            );
          }),
          const Divider(),
          infoRow('Subtotal', '\$${subtotal.toStringAsFixed(2)} USD'),
          const SizedBox(height: 20),
          const Text(
            'Add special requests on the order review screen.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 25),
          const Text(
            'Orders are sent to the kitchen after you review your table and total. Pay at the counter.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => go('Checkout'),
            child: const Text('CONTINUE TO CHECKOUT'),
          ),
        ],
        const SizedBox(height: 70),
      ],
    ),
  );
  Widget information(bool mobile) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('After Work'),
        const SizedBox(height: 20),
        title(
          page == 'About'
              ? 'A place to come together.'
              : page == 'Contact'
              ? 'We’d love to welcome you.'
              : page == 'Events'
              ? 'Good things are on the way.'
              : page,
          size: mobile ? 45 : 65,
        ),
        const SizedBox(height: 25),
        Text(
          page == 'About'
              ? 'We believe the best moments happen around a table. After Work brings the warmth of your neighborhood café, the care of a thoughtful kitchen, and the energy of an evening lounge under one roof.\n\nFrom your first morning coffee to unforgettable evenings, there is always a place for you here.'
              : page == 'Contact'
              ? 'Our address, opening hours, phone number and social channels will be published here when the venue details are supplied.\n\nThis is a development preview. Reservations, newsletter subscriptions, and online orders are not being accepted yet.'
              : page == 'Events'
              ? 'Acoustic evenings, coffee workshops, and seasonal tasting experiences. Our calendar will be published once events and venue capacity are confirmed.'
              : 'This local development application stores account details, reservation records, orders, and newsletter consent in SQLite on the server. Passwords are hashed; payment card information is never collected. Account deletion is available from your profile. Operational records are retained without an account link. The business must supply its legal entity, retention policy, contact information, privacy policy and terms before production launch.',
          style: const TextStyle(fontSize: 17, height: 1.9, color: muted),
        ),
        const SizedBox(height: 35),
        photo('restaurant', height: 400, width: double.infinity),
        const SizedBox(height: 45),
      ],
    ),
  );
  Widget footer(bool mobile) => Container(
    width: double.infinity,
    color: brandBlue,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 25 : 64, vertical: 45),
    child: Column(
      children: [
        Wrap(
          spacing: 70,
          runSpacing: 30,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.asset(
                      'assets/images/after-work-logo.png',
                      width: 170,
                      height: 85,
                      fit: BoxFit.cover,
                      semanticLabel: 'After Work',
                    ),
                  ),
                  SizedBox(height: 15),
                  Text(
                    'Coffee by day. Dining by evening.\nMoments all night.',
                    style: TextStyle(
                      color: Color(0xFFDCE5FF),
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 230,
              child: Wrap(
                spacing: 18,
                runSpacing: 8,
                children:
                    [
                          'Home',
                          'Menu',
                          'Tables',
                          'About',
                          'Contact',
                          'Events',
                          'Reservations',
                          'Account',
                          'Admin',
                          'Gallery',
                          'Newsletter',
                        ]
                        .map(
                          (s) => TextButton(
                            onPressed: () => go(s),
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: ivory,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
            const SizedBox(
              width: 240,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A LITTLE SOMETHING TO LOOK FORWARD TO',
                    style: TextStyle(
                      color: Color(0xFFE8EDFF),
                      fontSize: 9,
                      letterSpacing: 1.3,
                    ),
                  ),
                  SizedBox(height: 15),
                  Text(
                    'Our doors will open soon.\nVenue details to be announced.',
                    style: TextStyle(
                      color: Color(0xFFDCE5FF),
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 35),
        const Divider(color: Color(0xFF496CC2)),
        Row(
          children: [
            const Expanded(
              child: Text(
                '© 2026 After Work · Development preview',
                style: TextStyle(color: Color(0xFFDCE5FF), fontSize: 9),
              ),
            ),
            TextButton(
              onPressed: () => go('Privacy & Terms'),
              child: const Text(
                'Privacy & Terms',
                style: TextStyle(color: Color(0xFFDCE5FF), fontSize: 9),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
