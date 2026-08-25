import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../platform/platform_models.dart' show PlatformUser;
import '../platform/platform_repository.dart' show platformUsersProvider;
import '../support/support_models.dart' show ticketPriorities;
import 'support_admin_models.dart';
import 'support_admin_repository.dart';

// ── Agents ────────────────────────────────────────────────────

Future<void> showSupportAgentSheet(
  BuildContext context, {
  SupportAgent? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AgentSheet(existing: existing),
  );
}

class _AgentSheet extends ConsumerStatefulWidget {
  const _AgentSheet({this.existing});

  final SupportAgent? existing;

  @override
  ConsumerState<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends ConsumerState<_AgentSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _department =
      TextEditingController(text: widget.existing?.department ?? '');
  late final TextEditingController _specialization =
      TextEditingController(text: widget.existing?.specialization ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late final TextEditingController _maxTickets = TextEditingController(
    // Seeded from the record, never left blank: the field is a primitive int
    // that defaults to 10 when the key is missing, so an empty box would
    // rewrite the agent's limit rather than leave it be.
    text: '${widget.existing?.maxConcurrentTickets ?? 10}',
  );

  PlatformUser? _user;
  late String _status = widget.existing?.status ?? agentStatuses.first;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _department.dispose();
    _specialization.dispose();
    _notes.dispose();
    _maxTickets.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isEdit && _user == null) {
      setState(() => _error = 'Pick the person who will staff the desk.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(supportAdminRepositoryProvider);
    final request = SupportAgentRequest(
      maxConcurrentTickets: int.tryParse(_maxTickets.text.trim()) ?? 10,
      department: _department.text,
      specialization: _specialization.text,
      notes: _notes.text,
      userId: _isEdit ? null : _user!.id,
      status: _isEdit ? null : _status,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateAgent(widget.existing!.id, request);
        ref.read(supportAgentsProvider.notifier).apply(updated);
      } else {
        await repo.createAgent(request);
        await ref.read(supportAgentsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Agent updated.' : 'Agent added to the desk.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that agent.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit ${widget.existing!.displayName}' : 'Add an agent',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add to the desk',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        if (!_isEdit) ...[
          _UserField(
            value: _user,
            onChanged: (user) => setState(() {
              _user = user;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Starting status',
              prefixIcon: Icon(Icons.circle_outlined),
            ),
            items: [
              for (final status in agentStatuses)
                DropdownMenuItem(value: status, child: Text(Fmt.label(status))),
            ],
            onChanged: (value) => setState(() => _status = value ?? _status),
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _department,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Department (optional)',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _specialization,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Specialisation (optional)',
            helperText: 'What they handle best — billing, integrations, and so on',
            prefixIcon: Icon(Icons.workspace_premium_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _maxTickets,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tickets at once',
            prefixIcon: Icon(Icons.confirmation_number_outlined),
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'A number is required.';
            // Matches the backend's @Min(1).
            return parsed < 1 ? 'At least one.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 14),
          Text(
            'Status and availability are changed from the agent list, not here.',
            style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// Which platform user becomes the agent.
///
/// An agent record wraps a user, not an employee, and each user can hold only
/// one — the backend refuses a second with "User is already a support agent".
class _UserField extends ConsumerWidget {
  const _UserField({required this.value, required this.onChanged});

  final PlatformUser? value;
  final ValueChanged<PlatformUser?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final users = ref.watch(platformUsersProvider);

    return users.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => MessageBanner.error(
        error is ApiException ? error.message : 'Could not load the users.',
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return Text(
            'There are no platform users to staff the desk with yet.',
            style: TextStyle(color: bos.danger, fontSize: 12.5, height: 1.45),
          );
        }
        return DropdownButtonFormField<int>(
          initialValue: value?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Person',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          items: [
            for (final user in state.items)
              DropdownMenuItem(
                value: user.id,
                child: Text(
                  '${user.fullName} · ${user.email}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            for (final user in state.items) {
              if (user.id == id) {
                onChanged(user);
                return;
              }
            }
            onChanged(null);
          },
          validator: (_) => value == null ? 'Pick a person.' : null,
        );
      },
    );
  }
}

// ── Categories ────────────────────────────────────────────────

Future<void> showSupportCategorySheet(
  BuildContext context, {
  SupportCategory? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategorySheet(existing: existing),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing});

  final SupportCategory? existing;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(supportAdminRepositoryProvider);
    final request = SupportCategoryRequest(
      name: _name.text,
      description: _description.text,
      // Carried through untouched: the app does not pick icons, and the field
      // is assigned unconditionally, so dropping it would clear one set on the
      // web.
      icon: widget.existing?.icon,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateCategory(widget.existing!.id, request);
        ref.read(supportCategoriesProvider.notifier).apply(updated);
      } else {
        await repo.createCategory(request);
        await ref.read(supportCategoriesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Category updated.' : 'Category added.'),
        ),
      );
    } on ApiException catch (e) {
      // A duplicate name is refused with a message naming it.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that category.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetFrame(
      title: _isEdit ? 'Edit category' : 'New category',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add category',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What belongs here (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── SLA policies ──────────────────────────────────────────────

Future<void> showSlaPolicySheet(
  BuildContext context, {
  SlaPolicy? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SlaSheet(existing: existing),
  );
}

class _SlaSheet extends ConsumerStatefulWidget {
  const _SlaSheet({this.existing});

  final SlaPolicy? existing;

  @override
  ConsumerState<_SlaSheet> createState() => _SlaSheetState();
}

class _SlaSheetState extends ConsumerState<_SlaSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  // Both seeded from the record. They are primitive ints on the DTO, assigned
  // unconditionally, so an empty box would promise an instant response.
  late final TextEditingController _firstResponse = TextEditingController(
    text: '${widget.existing?.firstResponseTimeHours ?? 4}',
  );
  late final TextEditingController _resolution = TextEditingController(
    text: '${widget.existing?.resolutionTimeHours ?? 24}',
  );

  late String _priority = widget.existing?.priority ?? 'MEDIUM';
  late bool _businessHoursOnly = widget.existing?.businessHoursOnly ?? true;
  late bool _active = widget.existing?.active ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _notes.dispose();
    _firstResponse.dispose();
    _resolution.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(supportAdminRepositoryProvider);
    final request = SlaPolicyRequest(
      name: _name.text,
      priority: _priority,
      firstResponseTimeHours: int.tryParse(_firstResponse.text.trim()) ?? 0,
      resolutionTimeHours: int.tryParse(_resolution.text.trim()) ?? 0,
      businessHoursOnly: _businessHoursOnly,
      active: _active,
      description: _description.text,
      // Only on create: the update never reads it, so offering it on an edit
      // would be a field that silently does nothing.
      notes: _isEdit ? null : _notes.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateSlaPolicy(widget.existing!.id, request);
        ref.read(slaPoliciesProvider.notifier).apply(updated);
      } else {
        await repo.createSlaPolicy(request);
        await ref.read(slaPoliciesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Policy updated.' : 'Policy added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that policy.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _hours(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'A number of hours is required.';
    return parsed < 1 ? 'At least one hour.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit policy' : 'New SLA policy',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add policy',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(
            labelText: 'Applies to',
            prefixIcon: Icon(Icons.priority_high_rounded),
          ),
          items: [
            for (final priority in ticketPriorities)
              DropdownMenuItem(
                value: priority,
                child: Text('${Fmt.label(priority)} priority'),
              ),
          ],
          onChanged: (value) => setState(() => _priority = value ?? _priority),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _firstResponse,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'First reply (h)',
                ),
                validator: _hours,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _resolution,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Resolved by (h)',
                ),
                validator: _hours,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              helperText: 'Kept on the record, but not editable afterwards',
              alignLabelWithHint: true,
            ),
          ),
        ],
        const SizedBox(height: 4),
        SwitchListTile(
          value: _businessHoursOnly,
          onChanged: (value) => setState(() => _businessHoursOnly = value),
          title: Text(
            'Business hours only',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'The clock stops overnight and at weekends',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          title: Text('In force', style: TextStyle(color: bos.text, fontSize: 14)),
          subtitle: Text(
            'Only one policy per priority should be in force at a time',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}

// ── Audit filter ──────────────────────────────────────────────

/// Narrows the audit trail.
///
/// The backend has one endpoint per filter rather than one with optional
/// parameters, so the two cannot be combined — picking a date range clears an
/// action type and vice versa. The sheet says so rather than letting somebody
/// set both and wonder which won.
Future<void> showAuditFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AuditFilterSheet(),
  );
}

class _AuditFilterSheet extends ConsumerStatefulWidget {
  const _AuditFilterSheet();

  @override
  ConsumerState<_AuditFilterSheet> createState() => _AuditFilterSheetState();
}

class _AuditFilterSheetState extends ConsumerState<_AuditFilterSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _actionType = TextEditingController(
    text: ref.read(auditFilterProvider).actionType ?? '',
  );

  // The filter carries ISO strings, which is what the endpoint's
  // @DateTimeFormat(ISO.DATE) expects; DateField deals in DateTime.
  late DateTime? _start = Fmt.parse(ref.read(auditFilterProvider).start);
  late DateTime? _end = Fmt.parse(ref.read(auditFilterProvider).end);

  @override
  void dispose() {
    _actionType.dispose();
    super.dispose();
  }

  void _apply() {
    final action = _actionType.text.trim();
    final controller = ref.read(auditFilterProvider.notifier);

    final start = _start;
    final end = _end;
    if (action.isNotEmpty) {
      controller.set(AuditFilter(actionType: action));
    } else if (start != null && end != null) {
      controller.set(
        AuditFilter(start: Fmt.isoDate(start), end: Fmt.isoDate(end)),
      );
    } else {
      controller.clear();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Narrow the trail',
      formKey: _formKey,
      error: null,
      onDismissError: () {},
      action: 'Apply',
      submitting: false,
      onSubmit: _apply,
      children: [
        TextFormField(
          controller: _actionType,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Action type',
            helperText: 'Exactly as it appears on a row, e.g. TICKET_ASSIGNED',
            prefixIcon: Icon(Icons.bolt_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        Text(
          _actionType.text.trim().isEmpty
              ? 'Or pick a date range'
              : 'A date range cannot be combined with an action type — clear '
                  'the box above to use one.',
          style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'From',
          value: _start,
          clearable: true,
          onChanged: (value) => setState(() => _start = value),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'To',
          value: _end,
          clearable: true,
          onChanged: (value) => setState(() => _end = value),
        ),
        if ((_start == null) != (_end == null)) ...[
          const SizedBox(height: 10),
          Text(
            'Both dates are needed for a range.',
            style: TextStyle(color: bos.danger, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () {
            ref.read(auditFilterProvider.notifier).clear();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.clear_rounded, size: 18),
          label: const Text('Show everything'),
        ),
      ],
    );
  }
}
