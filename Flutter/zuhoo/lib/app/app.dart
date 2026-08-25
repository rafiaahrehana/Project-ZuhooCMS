import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push/push_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'impersonation_banner.dart';
import 'router.dart';

class ZuhooApp extends ConsumerWidget {
  const ZuhooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);

    // Started here rather than awaited: nothing on screen depends on push
    // being ready, and blocking the first frame on a permission dialog would
    // be a worse cold start than the one this is meant to improve.
    ref.watch(pushInitProvider);

    // Both themes are built every time the accent changes, and Flutter picks
    // between them from `themeMode`. That is what makes "System" work without
    // the app having to watch the platform brightness itself — and what makes
    // the switch at sunset a repaint rather than a restart.
    return MaterialApp.router(
      title: 'Zuhoo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.accent),
      darkTheme: AppTheme.dark(settings.accent),
      themeMode: settings.mode,
      routerConfig: ref.watch(routerProvider),
      // Above the router, so the reminder cannot be navigated away from.
      builder: (context, child) =>
          ImpersonationScope(child: child ?? const SizedBox.shrink()),
    );
  }
}
