import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app_config.dart';
import 'providers/app_state.dart';
import 'screens/screens.dart';

void main() => runApp(ChangeNotifierProvider(
    create: (_) => AppState(), child: const DelightApp()));

class DelightApp extends StatelessWidget {
  const DelightApp({super.key});

  @override
  Widget build(BuildContext context) {
    const outline = BorderSide(color: AppConfig.borderColor, width: 1.3);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: AppConfig.brandName,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.light(
          primary: AppConfig.primaryColor,
          onPrimary: Colors.white,
          primaryContainer: AppConfig.selectedColor,
          onPrimaryContainer: AppConfig.textColor,
          secondary: AppConfig.primaryDarkColor,
          onSecondary: Colors.white,
          surface: AppConfig.surfaceColor,
          onSurface: AppConfig.textColor,
          error: AppConfig.primaryDarkColor,
        ),
        scaffoldBackgroundColor: AppConfig.surfaceColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppConfig.surfaceColor,
          foregroundColor: AppConfig.textColor,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppConfig.textColor,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
          iconTheme: IconThemeData(color: AppConfig.textColor),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: AppConfig.textColor,
            fontWeight: FontWeight.w900,
          ),
          titleLarge: TextStyle(
            color: AppConfig.textColor,
            fontWeight: FontWeight.w800,
          ),
          titleMedium: TextStyle(
            color: AppConfig.textColor,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: AppConfig.textColor),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppConfig.cardColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: outline,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppConfig.cardColor,
          hintStyle: const TextStyle(
            color: AppConfig.mutedTextColor,
            fontWeight: FontWeight.w500,
          ),
          prefixIconColor: AppConfig.mutedTextColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: outline,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: outline,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                const BorderSide(color: AppConfig.primaryColor, width: 1.6),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppConfig.surfaceColor,
          selectedColor: AppConfig.selectedColor,
          disabledColor: AppConfig.surfaceColor,
          checkmarkColor: AppConfig.textColor,
          labelStyle: const TextStyle(
            color: AppConfig.mutedTextColor,
            fontWeight: FontWeight.w800,
          ),
          secondaryLabelStyle: const TextStyle(
            color: AppConfig.textColor,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: outline,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppConfig.cardColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: outline,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppConfig.borderColor,
            disabledForegroundColor: AppConfig.mutedTextColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? AppConfig.selectedColor
                    : AppConfig.cardColor),
            foregroundColor: WidgetStateProperty.all(AppConfig.textColor),
            side: WidgetStateProperty.all(outline),
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const LocationScreen()),
  GoRoute(path: '/stores', builder: (_, __) => const StoreListScreen()),
  GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
  GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
  GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
  GoRoute(
      path: '/confirmation', builder: (_, __) => const ConfirmationScreen()),
  GoRoute(path: '/tracking', builder: (_, __) => const TrackingScreen()),
  GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
]);
