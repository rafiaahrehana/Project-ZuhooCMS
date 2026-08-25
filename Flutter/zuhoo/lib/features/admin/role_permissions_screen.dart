import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// What one role grants.
///
/// The whole set is sent on save, not a diff — `setPermissions` replaces the
/// role's permissions with whatever arrives, so the screen holds the complete
/// selection and posts all of it. That also means an accidental save with
/// nothing ticked would strip the role, which is why saving is explicit rather
/// than per-tick.
class RolePermissionsScreen extends ConsumerStatefulWidget {
  const RolePermissionsScreen({super.key, required this.role});

  final CustomRole role;

  static void open(BuildContext context, {required CustomRole role}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RolePermissionsScreen(role: role),
      ),
    );
  }

  @override
  ConsumerState<RolePermissionsScreen> createState() =>
      _RolePermissionsScreenState();
}

class _RolePermissionsScreenState
    extends ConsumerState<RolePermissionsScreen> {
  /// Null until the role's current set has loaded. Distinct from an empty set,
  /// which is a role that genuinely grants nothing.
  Set<String>? _selected;

  bool _saving = false;
  String? _error;

  /// Puts somebody into this role.
  ///
  /// Company owner only — narrower than the rest of this screen, which platform
  /// admins can also reach. An employee holds at most one custom role, so this
  /// moves them out of whatever they were in rather than adding a second.
  Future<void> _assign() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Put into ${widget.role.name}',
    );
    if (person == null || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .assignRole(widget.role.id, person.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${person.fullName} is now ${widget.role.name}.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not assign that role.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Takes somebody out of whatever role they hold. Keyed on the employee
  /// rather than the role, because that is how the endpoint is shaped — there
  /// is only ever one to remove.
  Future<void> _unassign() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Remove from their role',
    );
    if (person == null || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).unassignRole(person.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${person.fullName} has no custom role now.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that role.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setRolePermissions(widget.role.id, selected.toList());
      // Anyone in this role now holds a different set; their own permission
      // state is loaded at sign-in, so this only refreshes what the screen
      // reads back.
      ref.invalidate(rolePermissionsProvider(widget.role.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Permissions saved.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those permissions.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final catalogue = ref.watch(permissionCatalogueProvider);
    final current = ref.watch(rolePermissionsProvider(widget.role.id));
    // Assigning is the company owner's alone — see [customRoleAssignRoles].
    final canAssign =
        ref.watch(currentUserProvider)?.hasAnyRole(customRoleAssignRoles) ??
            false;

    // Seeded once, from the server's answer. After that the selection is the
    // screen's own, so re-reading would throw away unsaved ticks.
    if (_selected == null && current.hasValue) {
      _selected = current.value!.toSet();
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(widget.role.name),
        actions: [
          if (canAssign)
            PopupMenuButton<String>(
              enabled: !_saving,
              tooltip: 'People',
              onSelected: (value) =>
                  value == 'assign' ? _assign() : _unassign(),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'assign',
                  child: Text('Put somebody in this role'),
                ),
                PopupMenuItem(
                  value: 'unassign',
                  child: Text('Remove somebody from their role'),
                ),
              ],
            ),
          if (_selected != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${_selected!.length} on',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ),
            ),
        ],
      ),
      body: catalogue.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load the permission list.',
          onRetry: () => ref.invalidate(permissionCatalogueProvider),
        ),
        data: (all) {
          if (current.hasError) {
            return ErrorState(
              message: 'Could not load what this role currently grants.',
              onRetry: () =>
                  ref.invalidate(rolePermissionsProvider(widget.role.id)),
            );
          }
          final selected = _selected;
          if (selected == null) return const Loader();

          // Grouped by the module the backend labels each code with, so a long
          // flat list of two hundred codes becomes something you can scan.
          final groups = <String, List<PermissionOption>>{};
          for (final option in all) {
            groups.putIfAbsent(option.group, () => []).add(option);
          }
          final names = groups.keys.toList()..sort();

          return Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: MessageBanner.error(
                    _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: names.length,
                  itemBuilder: (context, index) {
                    final name = names[index];
                    final options = groups[name]!;
                    final onCount =
                        options.where((o) => selected.contains(o.code)).length;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ExpansionTile(
                          title: Text(
                            Fmt.label(name),
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '$onCount of ${options.length}',
                            style: TextStyle(color: bos.muted, fontSize: 12),
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          children: [
                            for (final option in options)
                              CheckboxListTile(
                                value: selected.contains(option.code),
                                onChanged: _saving
                                    ? null
                                    : (checked) => setState(() {
                                          if (checked ?? false) {
                                            selected.add(option.code);
                                          } else {
                                            selected.remove(option.code);
                                          }
                                        }),
                                title: Text(
                                  option.name,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  option.code,
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: bos.bgCard,
                  border: Border(top: BorderSide(color: bos.borderLight)),
                ),
                child: SafeArea(
                  top: false,
                  child: LoadingButton(
                    label: 'Save permissions',
                    loading: _saving,
                    icon: Icons.check_rounded,
                    onPressed: _save,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
