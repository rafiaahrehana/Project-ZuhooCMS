import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_models.dart';
import '../core/auth/permission_controller.dart';
import '../core/theme/bos_tokens.dart';
import '../shared/widgets/brand_mark.dart';
import '../shared/widgets/primitives.dart';
import '../shared/widgets/search_field.dart';
import 'nav_registry.dart';
import 'router.dart';

/// The app's answer to the web app's sidebar: every module a permission
/// gates, sourced from [buildNavGroups] so this list and Home's Quick
/// Actions can never drift apart the way two hand-maintained copies did.
///
/// Mirrors Angular's `showGroupLabels` split: a company owner or platform
/// staff member gets the grouped accordion (with search-free section
/// headers), everyone else gets every visible item flattened into one plain
/// list. A group left with exactly one visible item renders as a direct
/// link rather than a one-item accordion, for either audience.
///
/// Ninety-odd destinations is more than anyone scrolls through, so the list
/// is searchable. Searching collapses the accordion to flat results for the
/// same reason the web app's does: once you have typed, the grouping is
/// noise between you and the four items that matched.
class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  String _query = '';

  void _open(NavDestination item) {
    Navigator.of(context).pop();
    if (item.push) {
      context.push(item.path, extra: item.initialTabLabel);
    } else {
      context.go(item.path, extra: item.initialTabLabel);
    }
  }

  void _go(String path) {
    Navigator.of(context).pop();
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final perms = ref.watch(permissionControllerProvider);
    final expandedGroups = ref.watch(drawerExpandedGroupsProvider);

    final groups = buildNavGroups(user, perms);
    final grouped = showGroupedNav(user);
    final location = GoRouterState.of(context).matchedLocation;

    final matches = _query.isEmpty ? null : _search(groups, _query);

    return Drawer(
      backgroundColor: bos.bgCard,
      width: 304,
      child: SafeArea(
        child: Column(
          children: [
            _Header(user: user),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: AppSearchField(
                hint: 'Search modules',
                // Nothing here is a network call, so the default debounce only
                // adds lag between typing and the list narrowing.
                debounce: const Duration(milliseconds: 80),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Divider(height: 1, color: bos.borderLight),
            Expanded(
              child: matches != null
                  ? _results(bos, matches, location)
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: grouped
                          ? [
                              for (final group in groups)
                                _group(bos, group, location, expandedGroups),
                            ]
                          : [
                              for (final item in flattenGroups(groups))
                                _item(bos, item, location, nested: false),
                            ],
                    ),
            ),
            Divider(height: 1, color: bos.borderLight),
            _AccountBar(onGo: _go),
          ],
        ),
      ),
    );
  }

  /// Matches on the destination label and on its group's, so typing "finance"
  /// finds the items inside Finance even where none of them repeats the word.
  List<NavDestination> _search(List<NavGroup> groups, String query) {
    final q = query.toLowerCase();
    return [
      for (final group in groups)
        for (final item in group.items)
          if (item.label.toLowerCase().contains(q) ||
              group.label.toLowerCase().contains(q))
            item,
    ];
  }

  Widget _results(BosPalette bos, List<NavDestination> matches, String location) {
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing matches "$_query"',
        message: 'Try a shorter word, or the name of the module it lives in.',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final item in matches) _item(bos, item, location, nested: false),
      ],
    );
  }

  /// A group with exactly one visible item is a direct link, not a
  /// one-child accordion — same rule Angular's sidebar applies.
  ///
  /// Expansion is deliberately sticky: tapping the row only ever opens a
  /// group, never closes one — that is what the trailing arrow is for.
  /// Without that split, backing out of a screen you just opened from here
  /// (which drops you on a route no group holds any more) used to read as
  /// the group snapping shut on its own, which is not what anyone tapped for.
  Widget _group(
    BosPalette bos,
    NavGroup group,
    String location,
    Set<String> expandedGroups,
  ) {
    if (group.items.length == 1) {
      return _item(bos, group.items.first, location, nested: false);
    }

    final holdsCurrent = group.items.any((item) => item.path == location);
    final isExpanded = expandedGroups.contains(group.label) || holdsCurrent;
    final controller = ref.read(drawerExpandedGroupsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => controller.expand(group.label),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 11, 4, 11),
                  child: Row(
                    children: [
                      Icon(
                        group.icon,
                        size: 20,
                        color: holdsCurrent ? bos.brandInk : bos.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: holdsCurrent ? bos.brandInk : bos.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => controller.toggle(group.label, isExpanded: isExpanded),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: bos.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: [
                for (final item in group.items) _item(bos, item, location, nested: true),
              ],
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _item(
    BosPalette bos,
    NavDestination item,
    String location, {
    required bool nested,
  }) {
    // Several destinations share one path and differ only by which tab they
    // open — ITAM's Hardware/Software/Offboarding are all `/assets`. The route
    // does not record the tab, so on those the honest answer is that we cannot
    // tell which one is showing, and highlighting all three would be worse
    // than highlighting none. The group header still lights up.
    final current = item.path == location && item.initialTabLabel == null;

    return Padding(
      padding: EdgeInsets.fromLTRB(nested ? 12 : 8, 1, 8, 1),
      child: Material(
        color: current ? bos.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _open(item),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.fromLTRB(nested ? 24 : 12, 11, 12, 11),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 19,
                  color: current ? bos.brandInk : bos.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: current ? bos.brandInk : bos.text,
                      fontSize: 14,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which groups the user has opened, kept outside the drawer's own widget
/// state because the drawer itself is torn down and rebuilt from scratch
/// every time it closes — an ordinary [State] field would forget everything
/// the moment the panel shut.
class DrawerExpansionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void expand(String label) {
    if (state.contains(label)) return;
    state = {...state, label};
  }

  void collapse(String label) {
    if (!state.contains(label)) return;
    state = {...state}..remove(label);
  }

  void toggle(String label, {required bool isExpanded}) =>
      isExpanded ? collapse(label) : expand(label);
}

final drawerExpandedGroupsProvider =
    NotifierProvider<DrawerExpansionController, Set<String>>(
  DrawerExpansionController.new,
);

/// Who is signed in, and to what.
class _Header extends StatelessWidget {
  const _Header({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final u = user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          if (u == null)
            const BrandMark(size: 44)
          else
            Avatar(
              initials: u.initials,
              imageUrl: u.profileImageUrl,
              size: 44,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u?.fullName.trim().isNotEmpty == true ? u!.fullName : 'Zuhoo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (u != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    u.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.brandInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    u.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The account actions that belong to the person rather than to a module, and
/// so are deliberately not in [buildNavGroups] — that table is the module
/// list, and mixing "Change password" into it would put a session action
/// inside a permission-gated group.
///
/// One gear rather than four icons: none of these get tapped often enough to
/// earn permanent real estate at the bottom of every drawer open.
class _AccountBar extends StatelessWidget {
  const _AccountBar({required this.onGo});

  final void Function(String path) onGo;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Account settings',
            icon: Icon(Icons.settings_outlined, size: 22, color: bos.textSecondary),
            onSelected: onGo,
            itemBuilder: (context) => [
              _entry(bos, Icons.person_outline_rounded, 'Profile', Routes.profile),
              _entry(bos, Icons.notifications_none_rounded, 'Alerts', Routes.alerts),
              _entry(bos, Icons.lock_outline_rounded, 'Change password',
                  Routes.changePassword),
              _entry(bos, Icons.alternate_email_rounded, 'Change email',
                  Routes.changeEmail),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _entry(
    BosPalette bos,
    IconData icon,
    String label,
    String path,
  ) =>
      PopupMenuItem(
        value: path,
        child: Row(
          children: [
            Icon(icon, size: 18, color: bos.textSecondary),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );
}
