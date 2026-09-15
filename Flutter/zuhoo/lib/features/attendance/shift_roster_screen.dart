import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'assign_shift_sheet.dart';
import 'attendance_admin_repository.dart';
import 'attendance_models.dart';

/// Which shift the roster is showing.
class RosterShiftController extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? shiftId) => state = shiftId;
}

final rosterShiftProvider =
    NotifierProvider<RosterShiftController, int?>(RosterShiftController.new);

/// Everybody on the shift in view.
final rosterProvider =
    FutureProvider.autoDispose<List<ShiftAssignment>>((ref) async {
  final shiftId = ref.watch(rosterShiftProvider);
  if (shiftId == null) return const [];
  final page = await ref
      .read(attendanceAdminRepositoryProvider)
      .assignmentsForShift(shiftId);
  return page.content;
});

/// Who is on which shift.
///
/// One shift at a time, because that is how the endpoint reads: there is no
/// "everybody's assignments" list, and building one from every shift would be
/// a call per shift for a screen nobody reads end to end.
class ShiftRosterScreen extends ConsumerWidget {
  const ShiftRosterScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ShiftRosterScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final shifts = ref.watch(activeShiftsProvider).value ?? const <Shift>[];
    final selected = ref.watch(rosterShiftProvider);
    final canAssign = ref
        .watch(permissionControllerProvider)
        .has(AttendancePermissions.shiftAssignmentCreate);

    // Pick the first shift as soon as the list arrives, so the screen has
    // something on it rather than an empty picker.
    if (selected == null && shifts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(rosterShiftProvider.notifier).set(shifts.first.id);
      });
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Who is on what')),
      floatingActionButton: canAssign
          ? FloatingActionButton.extended(
              onPressed: () async {
                await showAssignShiftSheet(context);
                ref.invalidate(rosterProvider);
              },
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Put somebody on'),
            )
          : null,
      body: shifts.isEmpty
          ? const EmptyState(
              icon: Icons.schedule_outlined,
              title: 'No shifts',
              message:
                  'Shifts are set up under HR rules. Until there is one, '
                  'there is nothing to roster.',
            )
          : ConfigList<ShiftAssignment>(
              async: ref.watch(rosterProvider),
              onRefresh: () async => ref.invalidate(rosterProvider),
              emptyIcon: Icons.groups_outlined,
              emptyTitle: 'Nobody on this shift',
              emptyMessage: 'Assignments appear here once somebody is put on '
                  'it.',
              errorMessage: 'Could not load the roster.',
              header: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilterBar(
                  selected: selected?.toString(),
                  options: [
                    for (final shift in shifts)
                      (value: shift.id.toString(), label: shift.name),
                  ],
                  onSelected: (value) => ref
                      .read(rosterShiftProvider.notifier)
                      .set(int.tryParse(value ?? '')),
                ),
              ),
              itemBuilder: (context, assignment) =>
                  _AssignmentRow(assignment: assignment),
            ),
    );
  }
}

class _AssignmentRow extends ConsumerStatefulWidget {
  const _AssignmentRow({required this.assignment});

  final ShiftAssignment assignment;

  @override
  ConsumerState<_AssignmentRow> createState() => _AssignmentRowState();
}

class _AssignmentRowState extends ConsumerState<_AssignmentRow> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(AttendanceAdminRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(attendanceAdminRepositoryProvider));
      ref.invalidate(rosterProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That did not go through.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final id = widget.assignment.id;
    if (id == null) return;

    final confirmed = await confirmAction(
      context,
      title: 'Take them off this shift?',
      message: 'The assignment is closed as of today. The record that it '
          'happened stays.',
      action: 'Take off',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    await _run((repo) => repo.endAssignment(id), 'Taken off.');
  }

  Future<void> _delete() async {
    final id = widget.assignment.id;
    if (id == null) return;

    final confirmed = await confirmAction(
      context,
      title: 'Delete this assignment?',
      message: 'It goes as if it never happened, which is only right when it '
          'was recorded by mistake. Taking somebody off keeps the record.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;
    await _run((repo) => repo.deleteAssignment(id), 'Deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    final permissions = ref.watch(permissionControllerProvider);
    final canUpdate =
        permissions.has(AttendancePermissions.shiftAssignmentUpdate);
    final canDelete =
        permissions.has(AttendancePermissions.shiftAssignmentDelete);

    final dates = assignment.assignmentEndDate == null
        ? 'from ${Fmt.dateShort(assignment.assignmentStartDate)}'
        : '${Fmt.dateShort(assignment.assignmentStartDate)} — '
            '${Fmt.dateShort(assignment.assignmentEndDate)}';

    return ConfigRow(
      title: assignment.employeeName ??
          'Employee #${assignment.employeeId ?? "?"}',
      subtitle: [
        dates,
        if (assignment.reason != null) assignment.reason!,
      ].join('  ·  '),
      active: assignment.active,
      inactiveLabel: 'Ended',
      busy: _busy,
      // The id is what every write keys on, and the "my shift" read does not
      // carry one. Without it there is nothing to act on.
      onEdit: canUpdate && assignment.id != null
          ? () => showEditAssignmentSheet(context, assignment: assignment)
          : null,
      actions: [
        if (canUpdate && assignment.active && assignment.id != null)
          RowAction(label: 'Take off the shift', onSelected: _end),
        if (canDelete && assignment.id != null)
          RowAction(label: 'Delete', destructive: true, onSelected: _delete),
      ],
    );
  }
}

/// Changing an assignment — different dates, or a different shift.
Future<void> showEditAssignmentSheet(
  BuildContext context, {
  required ShiftAssignment assignment,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditAssignmentSheet(assignment: assignment),
    );

class _EditAssignmentSheet extends ConsumerStatefulWidget {
  const _EditAssignmentSheet({required this.assignment});

  final ShiftAssignment assignment;

  @override
  ConsumerState<_EditAssignmentSheet> createState() =>
      _EditAssignmentSheetState();
}

class _EditAssignmentSheetState
    extends ConsumerState<_EditAssignmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _reason =
      TextEditingController(text: widget.assignment.reason ?? '');
  late final _notes =
      TextEditingController(text: widget.assignment.notes ?? '');
  late int? _shiftId = widget.assignment.shiftId;
  late DateTime? _from = Fmt.parse(widget.assignment.assignmentStartDate);
  late DateTime? _to = Fmt.parse(widget.assignment.assignmentEndDate);

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final employeeId = widget.assignment.employeeId;
    if (employeeId == null || _shiftId == null) {
      setState(() => _error = 'This assignment is missing the employee or the '
          'shift it belongs to.');
      return;
    }
    if (_from != null && _to != null && _to!.isBefore(_from!)) {
      setState(() => _error = 'The end cannot come before the start.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(attendanceAdminRepositoryProvider).updateAssignment(
            widget.assignment.id!,
            ShiftAssignmentRequest(
              employeeId: employeeId,
              shiftId: _shiftId!,
              assignmentStartDate:
                  _from == null ? null : Fmt.isoDate(_from!),
              assignmentEndDate: _to == null ? null : Fmt.isoDate(_to!),
              reason: _reason.text,
              notes: _notes.text,
            ),
          );
      ref.invalidate(rosterProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // Overlapping assignments are refused with a message naming the other
      // one, which is more use than anything this could invent.
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that assignment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final shifts = ref.watch(activeShiftsProvider).value ?? const <Shift>[];

    return FormSheetFrame(
      title: 'Change the assignment',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Text(
          widget.assignment.employeeName ?? 'This employee',
          style: TextStyle(
            color: bos.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _shiftId,
          decoration: const InputDecoration(labelText: 'Shift'),
          items: [
            for (final shift in shifts)
              DropdownMenuItem(value: shift.id, child: Text(shift.name)),
          ],
          onChanged: (value) => setState(() => _shiftId = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'From',
                value: _from,
                onChanged: (value) => setState(() => _from = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                label: 'Until',
                value: _to,
                clearable: true,
                emptyText: 'Open-ended',
                onChanged: (value) => setState(() => _to = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Why'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
      ],
    );
  }
}
