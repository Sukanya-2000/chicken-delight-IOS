import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/screens.dart';

void main() => runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const DelightApp()));

class DelightApp extends StatelessWidget {
  const DelightApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'Chicken Delight',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8102E), primary: const Color(0xFFC8102E), secondary: const Color(0xFFFFC72C), surface: const Color(0xFFFFFBF7)),
      scaffoldBackgroundColor: const Color(0xFFFFFBF7),
      textTheme: const TextTheme(headlineMedium: TextStyle(fontWeight: FontWeight.w900), titleLarge: TextStyle(fontWeight: FontWeight.w800), titleMedium: TextStyle(fontWeight: FontWeight.w700)),
      cardTheme: const CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)))),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // A finite minimum width keeps buttons valid inside Rows (for example
          // the cart promo action). Parent constraints still make primary
          // actions full-width where appropriate.
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ),
    routerConfig: _router,
  );
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const LocationScreen()),
  GoRoute(path: '/stores', builder: (_, __) => const StoreListScreen()),
  GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
  GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
  GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
  GoRoute(path: '/confirmation', builder: (_, __) => const ConfirmationScreen()),
  GoRoute(path: '/tracking', builder: (_, __) => const TrackingScreen()),
  GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
]);
