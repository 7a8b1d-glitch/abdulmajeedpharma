import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aph_mobile/core/theme/app_theme.dart';
import 'package:aph_mobile/core/localization/app_localizations.dart';

/// Root widget of the Abdulmajeedpharma mobile app.
class AphApp extends ConsumerWidget {
  const AphApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Abdulmajeedpharma',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.delegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar', 'YE'), // default Arabic (Yemen)
      routerConfig: router,
    );
  }
}

/// GoRouter provider (placeholder — full route table added in Phase 02).
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Abdulmajeedpharma — Home (placeholder)')),
        ),
      ),
    ],
  );
});
