import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'biometric_models.dart';
import 'biometric_repository.dart';
import 'biometric_sheets.dart';

/// The attendance terminals, and who is enrolled on them.
class BiometricScreen extends ConsumerStatefulWidget {
  const BiometricScreen({super.key});

  @override
  ConsumerState<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends ConsumerState<BiometricScreen> {
  int? _busyId;

  /// Status, online and sync all answer with an empty body, so the row is
  /// rebuilt from what was asked for rather than from what came back.
  Future<void> _run(
    int id,
    Future<void> Function() action,
    String failure, {
    BiometricDevice? optimistic,
    String? success,
  }) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (optimistic != null) {
        ref.read(biometricDevicesProvider.notifier).apply(optimistic);
      } else {
        await ref.read(biometricDevicesProvider.notifier).refresh();
      }
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _setStatus(BiometricDevice device) async {
    final status = await pickOne(
      context,
      current: device.status,
      options: [
        for (final option in biometricDeviceStatuses)
          (value: option, label: Fmt.label(option)),
      ],
    );
    if (status == null || status == device.status || !mounted) return;

    final repo = ref.read(biometricRepositoryProvider);
    await _run(
      device.id,
      () => repo.setDeviceStatus(device.id, status),
      'Could not change that status.',
      optimistic: _withStatus(device, status: status),
    );
  }

  Future<void> _toggleOnline(BiometricDevice device) async {
    final online = !device.isOnline;
    final repo = ref.read(biometricRepositoryProvider);
    await _run(
      device.id,
      () => repo.setDeviceOnline(device.id, online),
      'Could not change that.',
      optimistic: _withStatus(device, online: online),
    );
  }

  Future<void> _sync(BiometricDevice device) async {
    final repo = ref.read(biometricRepositoryProvider);
    // Refreshes rather than patching: the sync time comes from the server.
    await _run(
      device.id,
      () => repo.recordSync(device.id),
      'Could not record that sync.',
      success: '${device.deviceName} synchronised.',
    );
  }

  Future<void> _delete(BiometricDevice device) async {
    final bos = Theme.of(context).bos;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${device.deviceName}?'),
        content: Text(
          device.totalEnrollments == 0
              ? 'Attendance already recorded through it is unaffected.'
              : 'The ${device.totalEnrollments} people enrolled on it would '
                  'have to enrol again elsewhere. Attendance already recorded '
                  'is unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: bos.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = device.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(biometricRepositoryProvider).deleteDevice(device.id);
      ref.read(biometricDevicesProvider.notifier).remove(device.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${device.deviceName} removed.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove that device.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Opens one person's enrollments, whoever is picked.
  Future<void> _lookUpPerson() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Whose enrollments?',
    );
    if (person == null || !mounted) return;
    EnrollmentsScreen.open(
      context,
      employeeId: person.id,
      name: person.fullName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Terminals')),
        body: const Loader(),
      );
    }

    if (!permissions.has(BiometricPermissions.view)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Terminals')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Attendance terminals are managed by whoever holds the biometric '
              'permissions. Your owner can grant them.',
        ),
      );
    }

    final canManage = permissions.has(BiometricPermissions.manage);
    final filter = ref.watch(deviceFilterProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Terminals'),
        actions: [
          IconButton(
            onPressed: _lookUpPerson,
            tooltip: 'Look up a person',
            icon: const Icon(Icons.person_search_outlined),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showDeviceSheet(context),
              backgroundColor: bos.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            )
          : null,
      body: ConfigList<BiometricDevice>(
        async: ref.watch(biometricDevicesProvider),
        onRefresh: ref.read(biometricDevicesProvider.notifier).refresh,
        emptyIcon: Icons.fingerprint_rounded,
        emptyTitle: filter == null ? 'No terminals yet' : 'None like that',
        emptyMessage: filter == null
            ? 'Add the readers people check in and out on. Enrolling happens '
                'at the terminal itself, not here.'
            : 'Try another filter, or clear it to see the whole estate.',
        errorMessage: 'Could not load the terminals.',
        header: FilterBar(
          selected: filter,
          onSelected: ref.read(deviceFilterProvider.notifier).set,
          options: [
            (value: null, label: 'All'),
            (value: onlineDevicesFilter, label: 'Online now'),
            for (final status in biometricDeviceStatuses)
              (value: status, label: Fmt.label(status)),
          ],
        ),
        itemBuilder: (context, device) => _DeviceCard(
          device: device,
          busy: _busyId == device.id,
          onEdit:
              canManage ? () => showDeviceSheet(context, existing: device) : null,
          onSetStatus: canManage ? () => _setStatus(device) : null,
          onToggleOnline: canManage ? () => _toggleOnline(device) : null,
          onSync: canManage ? () => _sync(device) : null,
          onDelete: canManage ? () => _delete(device) : null,
        ),
      ),
    );
  }
}

/// Rebuilds a device with one field changed.
///
/// The status and online endpoints answer with an empty body, so there is
/// nothing to parse — the row is rebuilt from what was asked for, and only
/// after the call has succeeded.
BiometricDevice _withStatus(
  BiometricDevice device, {
  String? status,
  bool? online,
}) =>
    BiometricDevice(
      id: device.id,
      deviceName: device.deviceName,
      deviceId: device.deviceId,
      status: status ?? device.status,
      isOnline: online ?? device.isOnline,
      portNumber: device.portNumber,
      matchThreshold: device.matchThreshold,
      enabledForCheckIn: device.enabledForCheckIn,
      enabledForCheckOut: device.enabledForCheckOut,
      totalEnrollments: device.totalEnrollments,
      deviceType: device.deviceType,
      ipAddress: device.ipAddress,
      location: device.location,
      department: device.department,
      notes: device.notes,
      manufacturer: device.manufacturer,
      model: device.model,
      firmwareVersion: device.firmwareVersion,
      lastSyncTime: device.lastSyncTime,
      maxEnrollments: device.maxEnrollments,
    );

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.busy,
    this.onEdit,
    this.onSetStatus,
    this.onToggleOnline,
    this.onSync,
    this.onDelete,
  });

  final BiometricDevice device;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onSetStatus;
  final VoidCallback? onToggleOnline;
  final VoidCallback? onSync;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final capacity = device.capacityUsed;

    final actions = <RowAction>[
      if (onEdit != null) RowAction(label: 'Edit', onSelected: onEdit!),
      if (onSetStatus != null)
        RowAction(label: 'Change status', onSelected: onSetStatus!),
      if (onToggleOnline != null)
        RowAction(
          label: device.isOnline ? 'Mark offline' : 'Mark online',
          onSelected: onToggleOnline!,
        ),
      if (onSync != null)
        RowAction(label: 'Record a sync', onSelected: onSync!),
      if (onDelete != null)
        RowAction(label: 'Remove', destructive: true, onSelected: onDelete!),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Reachability is the thing an operator scans for, so it is a
                // dot at the start of the line rather than a word at the end.
                Container(
                  height: 8,
                  width: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: device.isOnline ? bos.brand : bos.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    device.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(device.status, dense: true),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (actions.isNotEmpty)
                  PopupMenuButton<int>(
                    onSelected: (index) => actions[index].onSelected(),
                    itemBuilder: (context) => [
                      for (var i = 0; i < actions.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Text(
                            actions[i].label,
                            style: actions[i].destructive
                                ? TextStyle(color: bos.danger)
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (device.deviceType != null) Fmt.label(device.deviceType),
                device.usage,
                if (device.whereAndHow.isNotEmpty) device.whereAndHow,
              ].join(' · '),
              maxLines: 2,
              style: TextStyle(color: bos.muted, fontSize: 12, height: 1.4),
            ),
            if (capacity != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: capacity,
                  minHeight: 5,
                  backgroundColor: bos.borderLight,
                  color: capacity >= 0.9 ? bos.warning : bos.brand,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              [
                capacity == null
                    ? '${device.totalEnrollments} enrolled'
                    : '${device.totalEnrollments} of ${device.maxEnrollments} '
                        'enrolled',
                if (device.lastSyncTime != null)
                  'synced ${Fmt.relative(device.lastSyncTime)}'
                else
                  'never synced',
              ].join(' · '),
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// What one person is enrolled on, and a way to revoke it.
class EnrollmentsScreen extends ConsumerWidget {
  const EnrollmentsScreen({
    super.key,
    required this.employeeId,
    required this.name,
  });

  final int employeeId;
  final String name;

  static void open(
    BuildContext context, {
    required int employeeId,
    required String name,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EnrollmentsScreen(employeeId: employeeId, name: name),
      ),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    BiometricEnrollment enrollment,
  ) async {
    final bos = Theme.of(context).bos;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke this enrollment?'),
        content: Text(
          '$name would no longer be recognised by '
          '${enrollment.deviceName ?? 'that terminal'}, and would have to '
          'enrol again at it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: bos.danger),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(biometricRepositoryProvider)
          .deleteEnrollment(enrollment.id);
      ref.invalidate(enrollmentsProvider(employeeId));
      messenger.showSnackBar(const SnackBar(content: Text('Revoked.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not revoke that enrollment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final canManage =
        ref.watch(permissionControllerProvider).has(BiometricPermissions.manage);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(name)),
      body: ConfigList<BiometricEnrollment>(
        async: ref.watch(enrollmentsProvider(employeeId)),
        onRefresh: () async => ref.invalidate(enrollmentsProvider(employeeId)),
        emptyIcon: Icons.fingerprint_rounded,
        emptyTitle: 'Not enrolled anywhere',
        emptyMessage:
            '$name has no biometric on file. Enrolling is done at the terminal '
            'itself.',
        errorMessage: 'Could not load those enrollments.',
        itemBuilder: (context, enrollment) => ConfigRow(
          title: enrollment.deviceName ?? 'Terminal ${enrollment.deviceId}',
          active: enrollment.isUsable,
          inactiveLabel: enrollment.enrolled ? 'Suspended' : 'Not enrolled',
          subtitle: [
            if (enrollment.biometricType != null)
              Fmt.label(enrollment.biometricType),
            if (enrollment.enrollmentDate != null)
              'since ${Fmt.date(enrollment.enrollmentDate)}',
            if (enrollment.failureRate != null)
              '${Fmt.percent((enrollment.failureRate! * 100).round())} failed',
          ].join(' · '),
          trailingLabel: enrollment.lastVerifiedTime == null
              ? 'never used'
              : Fmt.relative(enrollment.lastVerifiedTime),
          actions: [
            if (canManage)
              RowAction(
                label: 'Revoke',
                destructive: true,
                onSelected: () => _revoke(context, ref, enrollment),
              ),
          ],
        ),
      ),
    );
  }
}
