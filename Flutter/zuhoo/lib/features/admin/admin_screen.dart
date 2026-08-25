import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart' show Department;
import 'admin_form_sheets.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'role_permissions_screen.dart';

/// Company setup: the lists everything else is chosen from.
///
/// Each tab is gated on the permission its own endpoints check, so an
/// administrator sees only what they could actually load — and the screen
/// disappears entirely for somebody with none of them.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);
    final user = ref.watch(currentUserProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Setup')),
        body: const Loader(),
      );
    }

    final canRoles = user?.hasAnyRole(customRoleRoles) ?? false;

    final tabs = <({String label, Widget view, VoidCallback? create})>[
      if (permissions.has(AdminPermissions.departmentView))
        (
          label: 'Departments',
          view: const _DepartmentsTab(),
          create: permissions.has(AdminPermissions.departmentCreate)
              ? () => showDepartmentSheet(context)
              : null,
        ),
      if (permissions.has(AdminPermissions.designationView))
        (
          label: 'Grades',
          view: const _DesignationsTab(),
          create: permissions.has(AdminPermissions.designationCreate)
              ? () => showDesignationSheet(context)
              : null,
        ),
      if (permissions.has(AdminPermissions.announcementView))
        (
          label: 'Notices',
          view: const _AnnouncementsTab(),
          create: permissions.has(AdminPermissions.announcementCreate)
              ? () => showAnnouncementSheet(context)
              : null,
        ),
      if (permissions.has(AdminPermissions.serviceCategoryView))
        (
          label: 'Categories',
          view: const _CategoriesTab(),
          create: permissions.has(AdminPermissions.serviceCategoryCreate)
              ? () => showServiceCategorySheet(context)
              : null,
        ),
      if (canRoles)
        (
          label: 'Roles',
          view: const _RolesTab(),
          create: () => showRoleSheet(context),
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Setup')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Company setup needs administrator permissions. Your owner can '
              'grant them.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final create = tabs[tabController.index].create;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Setup'),
                  bottom: TabBar(
                    isScrollable: tabs.length > 3,
                    tabAlignment:
                        tabs.length > 3 ? TabAlignment.start : null,
                    tabs: [for (final tab in tabs) Tab(text: tab.label)],
                  ),
                ),
                floatingActionButton: create == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: create,
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New'),
                      ),
                body: TabBarView(children: [for (final tab in tabs) tab.view]),
              );
            },
          );
        },
      ),
    );
  }
}

class _DepartmentsTab extends ConsumerStatefulWidget {
  const _DepartmentsTab();

  @override
  ConsumerState<_DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends ConsumerState<_DepartmentsTab> {
  int? _busyId;

  Future<void> _toggle(Department row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(adminRepositoryProvider).toggleDepartment(row.id);
      ref.read(departmentsAdminProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that department.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(AdminPermissions.departmentUpdate);

    return ConfigList<Department>(
      async: ref.watch(departmentsAdminProvider),
      onRefresh: () => ref.read(departmentsAdminProvider.notifier).refresh(),
      emptyTitle: 'No departments yet',
      emptyMessage: 'Add one and people can be filed under it.',
      errorMessage: 'Could not load your departments.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: row.code,
        trailingLabel: row.employeeCount == null
            ? null
            : '${row.employeeCount} ${row.employeeCount == 1 ? 'person' : 'people'}',
        busy: _busyId == row.id,
        onEdit:
            canUpdate ? () => showDepartmentSheet(context, existing: row) : null,
        onToggle: canUpdate ? () => _toggle(row) : null,
      ),
    );
  }
}

class _DesignationsTab extends ConsumerStatefulWidget {
  const _DesignationsTab();

  @override
  ConsumerState<_DesignationsTab> createState() => _DesignationsTabState();
}

class _DesignationsTabState extends ConsumerState<_DesignationsTab> {
  int? _busyId;

  Future<void> _toggle(Designation row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(adminRepositoryProvider).toggleDesignation(row.id);
      ref.read(designationsAdminProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that grade.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(AdminPermissions.designationUpdate);

    return ConfigList<Designation>(
      async: ref.watch(designationsAdminProvider),
      onRefresh: () => ref.read(designationsAdminProvider.notifier).refresh(),
      emptyTitle: 'No grades yet',
      emptyMessage: 'Grades give job titles a structure to sort by.',
      errorMessage: 'Could not load your grades.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: [
          row.code,
          if (row.departmentName != null) row.departmentName!,
        ].join(' · '),
        trailingLabel: 'L${row.level}',
        busy: _busyId == row.id,
        onEdit: canUpdate
            ? () => showDesignationSheet(context, existing: row)
            : null,
        onToggle: canUpdate ? () => _toggle(row) : null,
      ),
    );
  }
}

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab();

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  int? _busyId;

  Future<void> _toggle(ServiceCategory row) async {
    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(adminRepositoryProvider).toggleServiceCategory(row.id);
      ref.read(serviceCategoriesAdminProvider.notifier).apply(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that category.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(AdminPermissions.serviceCategoryUpdate);

    return ConfigList<ServiceCategory>(
      async: ref.watch(serviceCategoriesAdminProvider),
      onRefresh: () =>
          ref.read(serviceCategoriesAdminProvider.notifier).refresh(),
      emptyTitle: 'No categories yet',
      emptyMessage: 'Categories group the services clients can request.',
      errorMessage: 'Could not load your categories.',
      itemBuilder: (context, row) => ConfigRow(
        title: row.name,
        active: row.active,
        subtitle: row.description,
        trailingLabel: '#${row.sortOrder}',
        busy: _busyId == row.id,
        onEdit: canUpdate
            ? () => showServiceCategorySheet(context, existing: row)
            : null,
        onToggle: canUpdate ? () => _toggle(row) : null,
      ),
    );
  }
}

class _AnnouncementsTab extends ConsumerStatefulWidget {
  const _AnnouncementsTab();

  @override
  ConsumerState<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends ConsumerState<_AnnouncementsTab> {
  int? _busyId;

  /// Publishing is one way — there is no unpublish — so it asks first.
  Future<void> _publish(AdminAnnouncement row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Publish “${row.title}”?'),
        content: const Text(
          'It goes onto the notice board for its audience. There is no way to '
          'unpublish it afterwards, and it cannot be edited once it is out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = row.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(adminRepositoryProvider).publishAnnouncement(row.id);
      ref.read(announcementsAdminProvider.notifier).apply(updated);
      messenger.showSnackBar(const SnackBar(content: Text('Published.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not publish that notice.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(AdminPermissions.announcementUpdate);

    return ConfigList<AdminAnnouncement>(
      async: ref.watch(announcementsAdminProvider),
      onRefresh: () => ref.read(announcementsAdminProvider.notifier).refresh(),
      emptyTitle: 'Nothing posted',
      emptyMessage: 'Notices you write appear here as drafts until published.',
      errorMessage: 'Could not load your notices.',
      itemBuilder: (context, row) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.title,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    row.published ? 'APPROVED' : 'PENDING',
                    label: row.published ? 'Published' : 'Draft',
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                row.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (row.audience != null)
                    Text(
                      Fmt.label(row.audience),
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  if (row.scheduledAt != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Scheduled ${Fmt.dateShort(row.scheduledAt)}',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
              if (canUpdate && row.isEditable) ...[
                const SizedBox(height: 10),
                if (_busyId == row.id)
                  const Loader(padding: 4)
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              showAnnouncementSheet(context, existing: row),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _publish(row),
                          icon: const Icon(Icons.send_rounded, size: 15),
                          label: const Text('Publish'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Removes a custom role.
///
/// The backend refuses one that still has people in it, and says so — which is
/// the right order of operations anyway: move them out first, then delete.
Future<void> _deleteRole(
  BuildContext context,
  WidgetRef ref,
  CustomRole role,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${role.name}?'),
      content: const Text(
        'Anyone still in this role has to be moved out of it first.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(adminRepositoryProvider).deleteRole(role.id);
    ref.invalidate(customRolesProvider);
    messenger.showSnackBar(const SnackBar(content: Text('Role deleted.')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not delete that role.')),
    );
  }
}

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final roles = ref.watch(customRolesProvider);

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async => ref.invalidate(customRolesProvider),
      child: roles.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your roles.',
          onRetry: () => ref.invalidate(customRolesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No custom roles',
                  message:
                      'A role is a named set of permissions you can put people '
                      'into.',
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final role = list[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  // A system role is shown for context but has no editor: what
                  // it grants is fixed by the backend, not by this company.
                  onTap: role.systemRole
                      ? null
                      : () => RolePermissionsScreen.open(context, role: role),
                  child: AppCard(
                    child: Row(
                      children: [
                        Icon(
                          role.systemRole
                              ? Icons.lock_outline_rounded
                              : Icons.shield_outlined,
                          size: 19,
                          color: role.systemRole ? bos.muted : bos.brandInk,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role.name,
                                style: TextStyle(
                                  color: role.active ? bos.text : bos.muted,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (role.description != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  role.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (role.systemRole)
                          Text(
                            'Built in',
                            style: TextStyle(color: bos.muted, fontSize: 11.5),
                          )
                        else
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'permissions') {
                                RolePermissionsScreen.open(context, role: role);
                              } else if (value == 'edit') {
                                await showRoleSheet(context, existing: role);
                              } else {
                                await _deleteRole(context, ref, role);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'permissions',
                                child: Text('Permissions'),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
