import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/form_sheet.dart';
import '../ai/ai_models.dart' show AiPermissions;
import 'workflow_models.dart';
import 'workflow_repository.dart';

// ── Templates ─────────────────────────────────────────────────

Future<void> showWorkflowSheet(
  BuildContext context, {
  WorkflowTemplate? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WorkflowSheet(existing: existing),
  );
}

class _WorkflowSheet extends ConsumerStatefulWidget {
  const _WorkflowSheet({this.existing});

  final WorkflowTemplate? existing;

  @override
  ConsumerState<_WorkflowSheet> createState() => _WorkflowSheetState();
}

class _WorkflowSheetState extends ConsumerState<_WorkflowSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  bool _submitting = false;
  bool _suggesting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Asks the assistant for a shape, then fills the form in from it.
  ///
  /// The stages it proposes cannot be created here — the endpoint saves
  /// nothing, and each stage is its own call — so they are listed for the
  /// author to add one at a time on the next screen.
  Future<void> _suggest() async {
    final goal = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _GoalDialog(),
    );
    if (goal == null || goal.trim().isEmpty || !mounted) return;

    setState(() {
      _suggesting = true;
      _error = null;
    });

    try {
      final suggestion =
          await ref.read(workflowRepositoryProvider).suggest(goal);
      if (!mounted) return;
      setState(() {
        if (suggestion.name.isNotEmpty) _name.text = suggestion.name;
        final lines = [
          if (suggestion.suggestion != null) suggestion.suggestion!,
          for (final stage in suggestion.stages)
            '${stage.name}'
                '${stage.purpose == null ? '' : ' — ${stage.purpose}'}'
                '${stage.needsApproval ? ' (needs approval)' : ''}',
        ];
        _description.text = lines.join('\n');
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not draft a workflow just now.');
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
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
    final repo = ref.read(workflowRepositoryProvider);
    final request = WorkflowTemplateRequest(
      name: _name.text,
      description: _description.text,
    );

    try {
      if (_isEdit) {
        final updated = await repo.update(widget.existing!.id, request);
        ref.read(workflowsProvider.notifier).apply(updated);
        ref.invalidate(workflowDetailProvider(widget.existing!.id));
      } else {
        await repo.create(request);
        await ref.read(workflowsProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Workflow updated.' : 'Workflow created — add its stages.',
          ),
        ),
      );
    } on ApiException catch (e) {
      // A duplicate name is refused with a message naming it.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that workflow.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canDraft =
        ref.watch(permissionControllerProvider).has(AiPermissions.chat);

    return FormSheetFrame(
      title: _isEdit ? 'Edit workflow' : 'New workflow',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Create it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 150,
          decoration: InputDecoration(
            labelText: 'Name',
            prefixIcon: const Icon(Icons.account_tree_outlined),
            // The assistant fills the form in rather than saving anything, so
            // it sits on the field it changes.
            suffixIcon: !canDraft || _isEdit
                ? null
                : IconButton(
                    onPressed: _suggesting ? null : _suggest,
                    tooltip: 'Draft one from a goal',
                    icon: _suggesting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                  ),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _description,
          maxLines: 5,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it is for (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 6),
          Text(
            'Clearing the description leaves the old one in place — the '
            'endpoint ignores an empty value rather than storing it.',
            style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// What the workflow is meant to achieve, in the author's own words.
class _GoalDialog extends StatefulWidget {
  const _GoalDialog();

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return AlertDialog(
      title: const Text('What should it achieve?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Describe the job in a sentence and a set of stages comes back to '
            'start from. Nothing is saved until you save it.',
            style: TextStyle(color: bos.muted, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Registering a new company for a client',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Never mind'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text),
          child: const Text('Draft it'),
        ),
      ],
    );
  }
}

// ── Stages ────────────────────────────────────────────────────

Future<void> showStageSheet(
  BuildContext context, {
  required int templateId,
  required int nextOrder,
  WorkflowStage? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StageSheet(
      templateId: templateId,
      nextOrder: nextOrder,
      existing: existing,
    ),
  );
}

class _StageSheet extends ConsumerStatefulWidget {
  const _StageSheet({
    required this.templateId,
    required this.nextOrder,
    this.existing,
  });

  final int templateId;

  /// One past the highest order already used, so a new stage lands at the end
  /// rather than colliding with something.
  final int nextOrder;

  final WorkflowStage? existing;

  @override
  ConsumerState<_StageSheet> createState() => _StageSheetState();
}

class _StageSheetState extends ConsumerState<_StageSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _order = TextEditingController(
    text: '${widget.existing?.stageOrder ?? widget.nextOrder}',
  );
  late final TextEditingController _days = TextEditingController(
    text: widget.existing?.estimatedDays == null
        ? ''
        : '${widget.existing!.estimatedDays}',
  );
  late final TextEditingController _sla = TextEditingController(
    text: widget.existing?.slaHours == null ? '' : '${widget.existing!.slaHours}',
  );
  late final TextEditingController _role =
      TextEditingController(text: widget.existing?.assigneeRole ?? '');
  late final TextEditingController _percent = TextEditingController(
    text: widget.existing?.paymentPercent == null
        ? ''
        : '${widget.existing!.paymentPercent}',
  );

  late bool _requiresApproval = widget.existing?.requiresApproval ?? false;
  late bool _requiresPayment = widget.existing?.requiresPayment ?? false;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _order.dispose();
    _days.dispose();
    _sla.dispose();
    _role.dispose();
    _percent.dispose();
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
    final repo = ref.read(workflowRepositoryProvider);
    final request = WorkflowStageRequest(
      name: _name.text,
      stageOrder: int.tryParse(_order.text.trim()) ?? widget.nextOrder,
      requiresApproval: _requiresApproval,
      requiresPayment: _requiresPayment,
      description: _description.text,
      estimatedDays: int.tryParse(_days.text.trim()),
      slaHours: int.tryParse(_sla.text.trim()),
      assigneeRole: _role.text,
      paymentPercent: int.tryParse(_percent.text.trim()),
    );

    try {
      if (_isEdit) {
        await repo.updateStage(widget.templateId, widget.existing!.id, request);
      } else {
        await repo.addStage(widget.templateId, request);
      }
      // Re-read rather than patch: every stage change bumps the template's
      // version, and a new stage's id is only known from the server.
      ref.invalidate(workflowDetailProvider(widget.templateId));
      await ref.read(workflowsProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Stage updated.' : 'Stage added.')),
      );
    } on ApiException catch (e) {
      // "Stage order N is already taken" is worth showing as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that stage.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// `@Min(1)` on all three optional numbers, so an empty box is the only way
  /// to say "not set" — zero is refused.
  String? _atLeastOne(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return 'A whole number.';
    return parsed < 1 ? 'At least one, or leave it empty.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit stage' : 'New stage',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add stage',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.flag_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        TextFormField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Position',
            helperText: 'Each stage has its own — two cannot share a position',
            prefixIcon: Icon(Icons.format_list_numbered_rounded),
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'A position is required.';
            return parsed < 1 ? 'One or higher.' : null;
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
                validator: _atLeastOne,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _sla,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SLA hours'),
                validator: _atLeastOne,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _role,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Assign to role (optional)',
            helperText: 'Free text — it is stored as written',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 3,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What happens here (optional)',
            alignLabelWithHint: true,
          ),
        ),
        SwitchListTile(
          value: _requiresApproval,
          onChanged: (value) => setState(() => _requiresApproval = value),
          title: Text(
            'Needs approval',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'Work stops here until somebody signs it off',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _requiresPayment,
          onChanged: (value) => setState(() => _requiresPayment = value),
          title: Text(
            'Needs payment',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          subtitle: Text(
            'A share of the price falls due before it can move on',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_requiresPayment) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _percent,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Share due (%)',
              prefixIcon: Icon(Icons.percent_rounded),
            ),
            validator: _atLeastOne,
          ),
        ],
      ],
    );
  }
}

/// Confirms removing a stage, then removes it.
Future<void> deleteStage(
  BuildContext context,
  WidgetRef ref, {
  required int templateId,
  required WorkflowStage stage,
}) async {
  final bos = Theme.of(context).bos;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove ${stage.name}?'),
      content: const Text(
        'Requests already partway through this workflow keep the stages they '
        'have. Only new ones follow the shorter path.',
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
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(workflowRepositoryProvider)
        .deleteStage(templateId, stage.id);
    ref.invalidate(workflowDetailProvider(templateId));
    await ref.read(workflowsProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(content: Text('${stage.name} removed.')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not remove that stage.')),
    );
  }
}
