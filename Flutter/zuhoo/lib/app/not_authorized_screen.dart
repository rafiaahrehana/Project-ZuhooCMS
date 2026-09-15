import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/primitives.dart';
import 'router.dart';

/// Landed on when a route is reached directly (deep link, restored back
/// stack, typed URL) that the signed-in account's role/permissions don't
/// actually unlock — the mobile counterpart to Angular's `RoleGuard` redirect
/// to `/forbidden`. The backend would refuse the underlying API calls either
/// way; this just avoids rendering the screen first and yanking it away.
class NotAuthorizedScreen extends StatelessWidget {
  const NotAuthorizedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not authorized')),
      body: Center(
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: "You don't have access to this",
          message: 'Ask an admin if you think this is a mistake.',
          action: FilledButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Back to home'),
          ),
        ),
      ),
    );
  }
}
