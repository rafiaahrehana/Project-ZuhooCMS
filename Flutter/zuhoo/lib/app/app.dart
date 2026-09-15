import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push/push_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'demo_banner.dart';
import 'impersonation_banner.dart';
import 'router.dart';

class ZuhooApp extends ConsumerWidget {
  const ZuhooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    ref.watch(pushInitProvider);
    return MaterialApp.router(
      title: 'Zuhoo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.accent),
      darkTheme: AppTheme.dark(settings.accent),
      themeMode: settings.mode,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => ImpersonationScope(
        child: DemoScope(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
