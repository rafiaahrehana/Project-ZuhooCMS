import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../ai/ai_models.dart' show AiPermissions;
import '../directory/directory_models.dart' show Department;
import 'admin_models.dart';
import 'admin_repository.dart';

// ── Departments ───────────────────────────────────────────────

Future<void> showDepartmentSheet(
  BuildContext context, {
  Department? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DepartmentSheet(existing: existing),
  );
}

class _DepartmentSheet extends ConsumerStatefulWidget {
  const _DepartmentSheet({this.existing});

  final Department? existing;

  @override
  ConsumerState<_DepartmentSheet> createState() => _DepartmentSheetState();
}

class _DepartmentSheetState extends ConsumerState<_DepartmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.code ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _budget = TextEditingController(
    text: widget.existing?.budget == null ? '' : '${widget.existing!.budget}',
  );

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    _budget.dispose();
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
    final repo = ref.read(adminRepositoryProvider);
    final request = DepartmentRequest(
      name: _name.text,
      code: _code.text,
      description: _description.text,
      budget: double.tryParse(_budget.text.trim()),
    );
    try {
      if (_isEdit) {
        final updated = await repo.updateDepartment(widget.existing!.id, request);
        ref.read(departmentsAdminProvider.notifier).apply(updated);
      } else {
        await repo.createDepartment(request);
        await ref.read(departmentsAdminProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Department updated.' : 'Department added.'),
        ),
      );
    } on ApiException catch (e) {
      // A duplicate name is refused with a message naming it.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that department.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetFrame(
      title: _isEdit ? 'Edit department' : 'New department',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add department',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return 'A name is required.';
            // Matches the backend's @Size(min = 2).
            return trimmed.length < 2 ? 'At least two characters.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code (optional)',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _budget,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Budget (optional)',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = double.tryParse(trimmed);
            if (parsed == null) return 'Enter a number, or leave it blank.';
            return parsed < 0 ? 'Cannot be negative.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── Designations ──────────────────────────────────────────────

Future<void> showDesignationSheet(
  BuildContext context, {
  Designation? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DesignationSheet(existing: existing),
  );
}

class _DesignationSheet extends ConsumerStatefulWidget {
  const _DesignationSheet({this.existing});

  final Designation? existing;

  @override
  ConsumerState<_DesignationSheet> createState() => _DesignationSheetState();
}

class _DesignationSheetState extends ConsumerState<_DesignationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.code ?? '');
  late final TextEditingController _level = TextEditingController(
    text: widget.existing == null ? '1' : '${widget.existing!.level}',
  );
  late final TextEditingController _category =
      TextEditingController(text: widget.existing?.employmentCategory ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  late int? _departmentId = widget.existing?.departmentId;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _level.dispose();
    _category.dispose();
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
    final repo = ref.read(adminRepositoryProvider);
    final request = DesignationRequest(
      name: _name.text,
      code: _code.text,
      level: int.parse(_level.text.trim()),
      description: _description.text,
      employmentCategory: _category.text,
      departmentId: _departmentId,
      active: widget.existing?.active,
    );
    try {
      if (_isEdit) {
        final updated =
            await repo.updateDesignation(widget.existing!.id, request);
        ref.read(designationsAdminProvider.notifier).apply(updated);
      } else {
        await repo.createDesignation(request);
        await ref.read(designationsAdminProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Grade updated.' : 'Grade added.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that grade.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments =
        ref.watch(departmentsAdminProvider).valueOrNull ?? const <Department>[];

    return FormSheetFrame(
      title: _isEdit ? 'Edit grade' : 'New grade',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add grade',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Senior Engineer',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A name is required.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: 'Stored upper-case, and has to be unique.',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A code is required.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _level,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Level',
            helperText: 'Lower is more senior. The list sorts by it.',
            prefixIcon: Icon(Icons.stairs_outlined),
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'Enter a whole number.';
            return parsed < 0 ? 'Cannot be negative.' : null;
          },
        ),
        const SizedBox(height: 16),
        if (departments.isNotEmpty) ...[
          DropdownButtonFormField<int?>(
            initialValue:
                departments.any((d) => d.id == _departmentId) ? _departmentId : null,
            decoration: const InputDecoration(
              labelText: 'Department (optional)',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final department in departments)
                DropdownMenuItem(
                  value: department.id,
                  child: Text(department.name),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _departmentId = value),
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _category,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Employment category (optional)',
            prefixIcon: Icon(Icons.category_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── Service categories ────────────────────────────────────────

Future<void> showServiceCategorySheet(
  BuildContext context, {
  ServiceCategory? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ServiceCategorySheet(existing: existing),
  );
}

class _ServiceCategorySheet extends ConsumerStatefulWidget {
  const _ServiceCategorySheet({this.existing});

  final ServiceCategory? existing;

  @override
  ConsumerState<_ServiceCategorySheet> createState() =>
      _ServiceCategorySheetState();
}

class _ServiceCategorySheetState
    extends ConsumerState<_ServiceCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _sortOrder = TextEditingController(
    text: '${widget.existing?.sortOrder ?? 0}',
  );
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
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
    final repo = ref.read(adminRepositoryProvider);
    final request = ServiceCategoryRequest(
      name: _name.text,
      sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
      description: _description.text,
    );
    try {
      if (_isEdit) {
        final updated =
            await repo.updateServiceCategory(widget.existing!.id, request);
        ref.read(serviceCategoriesAdminProvider.notifier).apply(updated);
      } else {
        await repo.createServiceCategory(request);
        await ref.read(serviceCategoriesAdminProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Category updated.' : 'Category added.'),
        ),
      );
    } on ApiException catch (e) {
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
            prefixIcon: Icon(Icons.folder_outlined),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A name is required.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Sort order',
            helperText: 'Lower shows first.',
            prefixIcon: Icon(Icons.sort_rounded),
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'Enter a whole number.';
            return parsed < 0 ? 'Cannot be negative.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ── Announcements ─────────────────────────────────────────────

Future<void> showAnnouncementSheet(
  BuildContext context, {
  AdminAnnouncement? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AnnouncementSheet(existing: existing),
  );
}

class _AnnouncementSheet extends ConsumerStatefulWidget {
  const _AnnouncementSheet({this.existing});

  final AdminAnnouncement? existing;

  @override
  ConsumerState<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends ConsumerState<_AnnouncementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');

  late String? _audience = widget.existing?.audience ?? 'ALL';
  late DateTime? _scheduledAt = Fmt.parse(widget.existing?.scheduledAt);
  late DateTime? _expiresAt = Fmt.parse(widget.existing?.expiresAt);
  bool _notifyAll = false;

  bool _submitting = false;
  bool _drafting = false;
  String? _error;

  /// Drafts the wording from an instruction.
  ///
  /// Nothing is saved by this — the draft lands in the two fields as text to
  /// edit, and the notice is still a draft until it is saved and published.
  Future<void> _draftWithAi() async {
    final instructions = await showDialog<String>(
      context: context,
      builder: (context) => const _InstructionsDialog(),
    );
    if (instructions == null || instructions.trim().isEmpty || !mounted) return;

    setState(() => _drafting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = await ref
          .read(adminRepositoryProvider)
          .draftAnnouncement(instructions);
      if (!mounted) return;
      setState(() {
        if (draft.title.trim().isNotEmpty) _title.text = draft.title.trim();
        if (draft.body.trim().isNotEmpty) _body.text = draft.body.trim();
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not draft that.')),
      );
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// `LocalDateTime` on the wire — midnight local, no zone. The backend only
  /// compares these against its own clock, so a date is enough.
  static String? _at(DateTime? date) =>
      date == null ? null : '${Fmt.isoDate(date)}T00:00:00';

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(adminRepositoryProvider);
    final request = AnnouncementRequest(
      title: _title.text,
      body: _body.text,
      audience: _audience,
      scheduledAt: _at(_scheduledAt),
      expiresAt: _at(_expiresAt),
      notifyAll: _notifyAll,
    );
    try {
      if (_isEdit) {
        final updated =
            await repo.updateAnnouncement(widget.existing!.id, request);
        ref.read(announcementsAdminProvider.notifier).apply(updated);
      } else {
        await repo.createAnnouncement(request);
        await ref.read(announcementsAdminProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Announcement updated.'
                : 'Saved as a draft. Publish it when ready.',
          ),
        ),
      );
    } on ApiException catch (e) {
      // "Cannot edit a published announcement" lands here.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save that announcement.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();
    // The draft endpoint resolves to the same generateRaw the assistant uses,
    // and that checks AI_CHAT.
    final canDraft =
        ref.watch(permissionControllerProvider).has(AiPermissions.chat);

    return FormSheetFrame(
      title: _isEdit ? 'Edit announcement' : 'New announcement',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Save draft',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _title,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Title',
            prefixIcon: Icon(Icons.campaign_outlined),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A title is required.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _body,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Message',
            alignLabelWithHint: true,
            suffixIcon: canDraft
                ? (_drafting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.auto_awesome_outlined, size: 19),
                        tooltip: 'Draft from an instruction',
                        onPressed: _submitting ? null : _draftWithAi,
                      ))
                : null,
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'There has to be something to say.'
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: announcementAudiences.contains(_audience)
              ? _audience
              : announcementAudiences.first,
          decoration: const InputDecoration(
            labelText: 'Who sees it',
            prefixIcon: Icon(Icons.groups_outlined),
          ),
          items: [
            for (final audience in announcementAudiences)
              DropdownMenuItem(
                value: audience,
                child: Text(Fmt.label(audience)),
              ),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => _audience = value ?? _audience),
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Publish on (optional)',
          value: _scheduledAt,
          enabled: !_submitting,
          firstDate: now,
          lastDate: DateTime(now.year + 2),
          emptyText: 'Publish by hand',
          onChanged: (date) => setState(() => _scheduledAt = date),
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Stop showing (optional)',
          icon: Icons.hourglass_bottom_rounded,
          value: _expiresAt,
          enabled: !_submitting,
          firstDate: now,
          lastDate: DateTime(now.year + 3),
          emptyText: 'No end date',
          onChanged: (date) => setState(() => _expiresAt = date),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _notifyAll,
          onChanged: _submitting
              ? null
              : (value) => setState(() => _notifyAll = value),
          title: Text(
            'Send a notification',
            style: TextStyle(color: bos.text, fontSize: 14.5),
          ),
          subtitle: Text(
            'Everyone in the audience gets a push, not just the notice board.',
            style: TextStyle(color: bos.muted, fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
          activeThumbColor: Colors.white,
        ),
      ],
    );
  }
}

// ── Custom roles ──────────────────────────────────────────────

Future<void> showRoleSheet(BuildContext context, {CustomRole? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RoleSheet(existing: existing),
  );
}

class _RoleSheet extends ConsumerStatefulWidget {
  const _RoleSheet({this.existing});

  final CustomRole? existing;

  @override
  ConsumerState<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends ConsumerState<_RoleSheet> {
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
    final repo = ref.read(adminRepositoryProvider);
    final request = CustomRoleRequest(
      name: _name.text,
      description: _description.text,
    );
    try {
      if (_isEdit) {
        await repo.updateRole(widget.existing!.id, request);
      } else {
        await repo.createRole(request);
      }
      ref.invalidate(customRolesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Role updated.'
                : 'Role created. Give it permissions next.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that role.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit role' : 'New role',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Create role',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Regional manager',
            prefixIcon: Icon(Icons.shield_outlined),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A name is required.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What it is for (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: bos.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A new role grants nothing until you tick permissions for it.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Asks what the notice should say.
///
/// A dialog rather than a field on the form: the instruction is input to the
/// assistant, not part of the notice, and leaving it in the sheet afterwards
/// would read as something that gets posted.
class _InstructionsDialog extends StatefulWidget {
  const _InstructionsDialog();

  @override
  State<_InstructionsDialog> createState() => _InstructionsDialogState();
}

class _InstructionsDialogState extends State<_InstructionsDialog> {
  final _instructions = TextEditingController();

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draft a notice'),
      content: TextField(
        controller: _instructions,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'office closed Thursday for maintenance, back Friday',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _instructions.text),
          child: const Text('Draft'),
        ),
      ],
    );
  }
}
