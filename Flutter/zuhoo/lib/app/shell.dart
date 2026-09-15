import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/bos_tokens.dart';
import '../features/alerts/notification_repository.dart';
import 'app_drawer.dart';
import 'quick_actions.dart';

/// Opens the drawer from inside a branch screen.
///
/// The drawer hangs off *this* Scaffold, but every tab renders its own
/// Scaffold inside it, so a plain `Scaffold.of(context)` in a tab finds the
/// inner one — which has no drawer. A key onto the shell's state is what lets
/// a screen several Scaffolds down still reach it.
final appShellScaffoldKey = GlobalKey<ScaffoldState>();

/// The menu button each tab puts in its own app bar.
///
/// It lives in the tab's bar rather than in a strip above it. The strip cost a
/// whole bar's height on every screen to hold one icon, and left the app
/// showing two stacked headers — the empty one with the hamburger, then the
/// screen's real title bar underneath.
class AppDrawerButton extends StatelessWidget {
  const AppDrawerButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'All modules',
        onPressed: () => appShellScaffoldKey.currentState?.openDrawer(),
      );
}

/// The signed-in frame: five tabs, each keeping its own navigation state.
///
/// Five destinations is the ceiling for a bottom bar — beyond that the labels
/// stop fitting and the targets get too small to hit reliably. The web app's
/// twelve nav groups do not translate; what does is the handful of things an
/// employee opens daily, with everything else reached from inside them.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      key: appShellScaffoldKey,
      backgroundColor: bos.bgPage,
      drawer: const AppDrawer(),
      body: navigationShell,
      // Only on Home: several other tabs (Leave, notably) already float their
      // own single-purpose action button, and stacking two FABs in the same
      // corner is worse than only offering the shortcut from one place.
      floatingActionButton: navigationShell.currentIndex == 0
          ? Builder(
              builder: (context) => FloatingActionButton(
                onPressed: () => showQuickActionSheet(context, ref),
                tooltip: 'Quick actions',
                child: const Icon(Icons.bolt_rounded),
              ),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: bos.border)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onTap,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.access_time_rounded),
              selectedIcon: Icon(Icons.access_time_filled_rounded),
              label: 'Attendance',
            ),
            const NavigationDestination(
              icon: Icon(Icons.event_available_outlined),
              selectedIcon: Icon(Icons.event_available_rounded),
              label: 'Leave',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: bos.danger,
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: bos.danger,
                child: const Icon(Icons.notifications_rounded),
              ),
              label: 'Alerts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(int index) {
    // Tapping the tab you are already on pops back to that branch's root,
    // which is the standard escape hatch out of a stack you drilled into.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
