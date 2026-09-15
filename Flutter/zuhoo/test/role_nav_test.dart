import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zuhoo/app/app_drawer.dart';
import 'package:zuhoo/app/nav_registry.dart';
import 'package:zuhoo/core/auth/auth_controller.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/core/auth/permission_controller.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';

/// What the navigation looks like from each side of the account.
///
/// The employee's rendering is a whole path that cannot be reached without
/// that person's password, so it is covered here instead: the drawer draws
/// itself from `buildNavGroups` and `showGroupedNav`, and both are plain
/// functions of the user and their permissions.
///
/// The permission set is deliberately generous in these tests — every code the
/// registry asks for. That isolates what is being checked: anything an
/// employee still cannot see is being withheld by *role*, which is the part a
/// permission grant must never be able to open.
AppUser _user(List<String> roles) => AppUser(
      id: 1,
      email: 'someone@example.com',
      fullName: 'Sabbir Rahman Khan',
      roles: roles,
      companyId: 1,
    );

/// Grants every permission, whatever is asked for.
///
/// The codes the registry gates on cannot be enumerated from outside it, so
/// rather than guess at a list, this answers yes to all of them. That is the
/// point of these tests: with nothing withheld by permission, anything an
/// employee still cannot reach is being withheld by role.
class _EverythingGranted extends PermissionState {
  const _EverythingGranted();

  @override
  bool has(String? permission) => true;

  @override
  bool hasAny(Iterable<String>? permissions) => true;
}

class _FixedPermissions extends PermissionController {
  _FixedPermissions(this._state);
  final PermissionState _state;

  @override
  PermissionState build() => _state;
}

Widget _drawerFor(AppUser user, PermissionState perms) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          drawer: AppDrawer(),
          body: SizedBox.shrink(),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _StubAuth(user)),
      permissionControllerProvider.overrideWith(() => _FixedPermissions(perms)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(AppAccent.emerald),
      routerConfig: router,
    ),
  );
}

class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;

  @override
  Future<AppUser?> build() async => _user;
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final state = tester.state<ScaffoldState>(find.byType(Scaffold).first);
  state.openDrawer();
  await tester.pumpAndSettle();
}

/// A group starts collapsed unless it holds the current route
/// (`DrawerExpansionController.build() => const {}`), so a real person
/// scrolls to and taps its header open before anything inside it is on
/// screen. The drawer's list is long enough (12 groups, ~90 destinations)
/// that `ListView` — `children:` or `.builder`, it makes no difference —
/// only mounts what's within its viewport plus cache extent, so a group
/// this far down genuinely isn't in the Element tree yet: `scrollUntilVisible`
/// is doing real work here, not a defensive no-op.
Future<void> _scrollUntilFound(WidgetTester tester, String label) async {
  final target = find.text(label);
  // The search field above the list carries its own internal `Scrollable`
  // (every `EditableText` does, for cursor scrolling) and sits earlier in
  // the tree, so `find.byType(Scrollable).first` grabs that one instead of
  // the drawer's own list. Dragging the `ListView` itself is unambiguous.
  final list = find.byType(ListView);
  for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Only meaningful in the grouped (accordion) drawer — a role that gets the
/// flat list instead has no group header to tap, since flat mode shows every
/// destination directly. See "renders flat for an employee" above.
Future<void> _expandGroup(WidgetTester tester, String label) async {
  await _scrollUntilFound(tester, label);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  const perms = _EverythingGranted();

  group('who gets the grouped navigation', () {
    test('the owner and the two platform admin roles, and nobody else', () {
      expect(showGroupedNav(_user(['COMPANY_OWNER'])), isTrue);
      expect(showGroupedNav(_user(['SUPER_ADMIN'])), isTrue);
      expect(showGroupedNav(_user(['SYSTEM_ADMIN'])), isTrue);

      expect(showGroupedNav(_user(['EMPLOYEE'])), isFalse);
      // Other platform staff are deliberately *not* in the accordion set,
      // even though they are platform users.
      expect(showGroupedNav(_user(['SUPPORT_AGENT'])), isFalse);
      expect(showGroupedNav(_user(['SALES_MANAGER'])), isFalse);
      expect(showGroupedNav(null), isFalse);
    });
  });

  group('what an employee is not shown', () {
    List<String> labelsFor(AppUser user) => [
          for (final g in buildNavGroups(user, perms))
            for (final i in g.items) i.label,
        ];

    test('owner-only items stay hidden however many permissions are granted',
        () {
      final employee = labelsFor(_user(['EMPLOYEE']));

      // These are gated on the role itself, so a generous permission set must
      // not open them.
      expect(employee, isNot(contains('Roles & Permissions')));
      expect(employee, isNot(contains('Plans & Upgrade')));
    });

    test('platform staff items stay hidden too', () {
      final employee = labelsFor(_user(['EMPLOYEE']));

      expect(employee, isNot(contains('The platform')));
      expect(employee, isNot(contains('Platform Users')));
      expect(employee, isNot(contains('Subscription Management')));
      expect(employee, isNot(contains('The queue')));
    });

    test('the dashboard swaps rather than disappearing', () {
      // The two are mutually exclusive by construction: an employee gets their
      // own, everybody else gets the company one. Neither role should ever see
      // both, and neither should see none.
      final employee = labelsFor(_user(['EMPLOYEE']));
      expect(employee, contains('My Dashboard'));
      expect(employee, isNot(contains('Overview')));

      final owner = labelsFor(_user(['COMPANY_OWNER']));
      expect(owner, contains('Overview'));
      expect(owner, isNot(contains('My Dashboard')));
    });
  });

  group('the drawer itself', () {
    testWidgets('renders flat for an employee — no group headers',
        (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['EMPLOYEE']), perms));
      await _openDrawer(tester);

      // Group headers are the accordion's; a flat list shows destinations
      // straight, so the headers must not be there.
      expect(find.text('Dashboards'), findsNothing);
      expect(find.text('Time & Leave'), findsNothing);

      // ...and the destinations themselves are.
      expect(find.text('My Dashboard'), findsWidgets);
    });

    testWidgets('renders grouped for the owner', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['COMPANY_OWNER']), perms));
      await _openDrawer(tester);

      expect(find.text('Dashboards'), findsOneWidget);
      // Twice by design: once as a quick-link inside "Dashboards", once as
      // its own group header below — same pattern as 'My Dashboard' above.
      expect(find.text('CRM'), findsWidgets);
    });

    // One role per test. Pumping a second tree over the first leaves the
    // already-open drawer in the overlay, so the finders go on seeing the
    // previous role's — which reads as a pass for whatever was expected to
    // still be there, and a failure for whatever was expected to be gone.
    testWidgets('the owner is offered the upgrade', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['COMPANY_OWNER']), perms));
      await _openDrawer(tester);
      await _expandGroup(tester, 'Administration');
      expect(find.text('Plans & Upgrade'), findsOneWidget);
    });

    testWidgets('the employee is not', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['EMPLOYEE']), perms));
      await _openDrawer(tester);
      expect(find.text('Plans & Upgrade'), findsNothing);
    });

    testWidgets('the owner keeps the account actions', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['COMPANY_OWNER']), perms));
      await _openDrawer(tester);
      await _expandGroup(tester, 'Administration');
      expect(find.text('Company Profile'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('the employee keeps them too', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['EMPLOYEE']), perms));
      await _openDrawer(tester);
      // Flat mode (see "renders flat for an employee" above) — every
      // destination is already on the list directly, nothing to expand.
      await _scrollUntilFound(tester, 'Change Password');
      expect(find.text('Company Profile'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('the header names the role in words', (tester) async {
      await tester.pumpWidget(_drawerFor(_user(['EMPLOYEE']), perms));
      await _openDrawer(tester);
      expect(find.text('Employee'), findsOneWidget);
      expect(find.text('Sabbir Rahman Khan'), findsOneWidget);
    });
  });
}
