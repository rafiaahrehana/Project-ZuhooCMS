import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../shared/widgets/form_sheet.dart';
import 'proposal_models.dart';
import 'request_controllers.dart';
import 'request_repository.dart';

/// Writes the proposal for a request — the first draft, and every revision
/// after the client asks for changes.
///
/// One sheet for both, because the backend has one endpoint for both: `PUT`
/// creates a DRAFT when the request has no proposal and updates the existing
/// one otherwise. Returns true when something was saved.
Future<bool> showProposalSheet(
  BuildContext context, {
  required int requestId,
  Proposal? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProposalSheet(requestId: requestId, existing: existing),
  );
  return saved ?? false;
}

class _ProposalSheet extends ConsumerStatefulWidget {
  const _ProposalSheet({required this.requestId, this.existing});

  final int requestId;
  final Proposal? existing;

  @override
  ConsumerState<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends ConsumerState<_ProposalSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _title = TextEditingController(text: widget.existing?.title);
  late final _stack = TextEditingController(text: widget.existing?.techStack);
  late final _timeline = TextEditingController(text: widget.existing?.timeline);
  late final _summary = TextEditingController(text: widget.existing?.summary);
  late final _budget =
      TextEditingController(text: widget.existing?.estimatedBudget);

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _stack.dispose();
    _timeline.dispose();
    _summary.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref.read(requestRepositoryProvider).saveProposal(
            widget.requestId,
            ProposalRequest(
              title: _title.text,
              techStack: _stack.text,
              timeline: _timeline.text,
              summary: _summary.text,
              estimatedBudget: _budget.text,
            ),
          );
      ref.invalidate(requestProposalProvider(widget.requestId));
      navigator.pop(true);
    } on ApiException catch (e) {
      // The backend refuses an edit once the proposal is sent or accepted.
      // [Proposal.canEdit] keeps the form from being offered in those states,
      // so getting here means the status moved while the sheet was open —
      // show what it said rather than a generic failure.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the proposal.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRevision =
        widget.existing?.status == ProposalStatus.changesRequested;

    return FormSheetFrame(
      title: widget.existing == null ? 'Draft a proposal' : 'Edit the proposal',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save draft',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Text(
          isRevision
              ? 'The client asked for changes. Saving keeps this a revision — '
                  'it goes back to them only when you send it again.'
              : 'What you intend to build, ahead of the formal quotation. '
                  'Saving does not send it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Inventory system for three warehouses',
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A title is required.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _stack,
          decoration: const InputDecoration(
            labelText: 'Tech stack (optional)',
            hintText: 'Flutter, Spring Boot, PostgreSQL',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _timeline,
          decoration: const InputDecoration(
            labelText: 'Timeline (optional)',
            hintText: '10-12 weeks, two milestones',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _budget,
          // Free text rather than a number: "৳ 4-6 lakh" and "depends on the
          // final scope" are both honest pre-sales answers, which is why the
          // backend stores it as a String.
          decoration: const InputDecoration(
            labelText: 'Estimated budget (optional)',
            hintText: 'BDT 4-6 lakh',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _summary,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Summary (optional)',
            hintText: 'The approach, what is in scope, and what is not.',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
