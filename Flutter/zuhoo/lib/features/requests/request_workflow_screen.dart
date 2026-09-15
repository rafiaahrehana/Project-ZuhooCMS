import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/employee_picker.dart';
import '../../shared/widgets/form_sheet.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'request_controllers.dart';
import 'request_models.dart';
import 'request_repository.dart';
import 'request_workflow_models.dart';

/// The stages a request walks through.
final stageProgressProvider =
    FutureProvider.autoDispose.family<StageProgress, int>(
  (ref, id) => ref.read(requestRepositoryProvider).stageProgress(id),
);

/// The sign-offs raised against a request.
final requestApprovalsProvider =
    FutureProvider.autoDispose.family<List<StageApproval>, int>(
  (ref, id) => ref.read(requestRepositoryProvider).approvalsForRequest(id),
);

/// The work sitting under a request.
final requestTasksProvider =
    FutureProvider.autoDispose.family<List<RequestTask>, int>(
  (ref, id) => ref.read(requestRepositoryProvider).tasks(id),
);

/// Everything staff can do to a request that a client cannot: move it through
/// its workflow, break it into tasks, hand it over, and quote for it.
///
/// A separate screen from the request detail rather than more tabs on it. The
/// detail screen is what a client sees too; this is the back office, and every
/// endpoint behind it is `hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')`.
class RequestWorkflowScreen extends ConsumerWidget {
  const RequestWorkflowScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RequestWorkflowScreen(id: id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestDetailProvider(id));
    final request = async.value;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Working on it'),
        actions: [
          if (request != null && request.isOpen)
            IconButton(
              tooltip: 'Draft a reply',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => showDraftReplySheet(context, id: id),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that request.',
          onRetry: () => ref.invalidate(requestDetailProvider(id)),
        ),
        data: (request) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async {
            ref.invalidate(requestDetailProvider(id));
            ref.invalidate(stageProgressProvider(id));
            ref.invalidate(requestApprovalsProvider(id));
            ref.invalidate(requestTasksProvider(id));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _WhoAndWhat(request: request),
              const SizedBox(height: 20),
              _Stages(request: request),
              const SizedBox(height: 20),
              _Quotation(request: request),
              const SizedBox(height: 20),
              _Tasks(request: request),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Who has it, and what state it is in ───────────────────────

class _WhoAndWhat extends ConsumerStatefulWidget {
  const _WhoAndWhat({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_WhoAndWhat> createState() => _WhoAndWhatState();
}

class _WhoAndWhatState extends ConsumerState<_WhoAndWhat> {
  bool _busy = false;

  Future<void> _run(
    Future<ServiceRequest> Function(RequestRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(requestRepositoryProvider));
      ref.invalidate(requestDetailProvider(widget.request.id));
      ref.invalidate(stageProgressProvider(widget.request.id));
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

  Future<void> _handOver() async {
    final person = await EmployeePicker.show(context, title: 'Who takes it?');
    if (person == null) return;
    await _run(
      (repo) => repo.assignTo(widget.request.id, person.id),
      'Handed to ${person.fullName}.',
    );
  }

  Future<void> _changeStatus() async {
    final status = await pickOne(
      context,
      options: [
        for (final value in _settableStatuses)
          (value: value, label: Fmt.label(value)),
      ],
      current: widget.request.status,
    );
    if (status == null || status == widget.request.status || !mounted) return;

    // The history is only as useful as the reasons in it, so this asks —
    // but the backend does not insist, and neither does this.
    final reason = await askForText(
      context,
      title: 'Why the change?',
      message: 'Goes on the request history. You can leave it blank.',
      label: 'Reason',
      action: 'Change it',
    );
    if (!mounted) return;
    await _run(
      (repo) => repo.changeStatus(widget.request.id, status, reason: reason),
      'Moved to ${Fmt.label(status)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final request = widget.request;
    final open = request.isOpen;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.title,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(request.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 15, color: bos.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  request.assignedEmployeeName ?? 'Nobody has it yet',
                  style: TextStyle(
                    color: request.assignedEmployeeName == null
                        ? bos.warning
                        : bos.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (open) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: LoadingButton(
                    label: request.assignedEmployeeName == null
                        ? 'Hand it to somebody'
                        : 'Hand it over',
                    icon: Icons.person_add_alt_outlined,
                    loading: _busy,
                    onPressed: _handOver,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _changeStatus,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Change status'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The statuses somebody would set by hand.
///
/// QUOTATION_PENDING is left out because quoting sets it, RESUBMITTED because
/// only a client resubmitting sets it, and CANCELLED because withdrawing has
/// its own endpoint that also checks who is allowed to.
const _settableStatuses = <String>[
  RequestStatus.pending,
  RequestStatus.assigned,
  RequestStatus.inProgress,
  RequestStatus.waitingClient,
  RequestStatus.underReview,
  RequestStatus.completed,
  RequestStatus.rejected,
];

// ── The workflow stages ───────────────────────────────────────

class _Stages extends ConsumerStatefulWidget {
  const _Stages({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_Stages> createState() => _StagesState();
}

class _StagesState extends ConsumerState<_Stages> {
  bool _busy = false;

  Future<void> _advance(StageStep next) async {
    final confirmed = await confirmAction(
      context,
      title: 'Finish this stage?',
      message: next.requiresApproval
          ? 'This stage needs signing off first. Pressing on raises the '
              'approval request and stops there — somebody else has to '
              'approve it before the request can move.'
          : 'Marks the current stage done and moves on to the next one.',
      action: next.requiresApproval ? 'Ask for approval' : 'Move on',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(requestRepositoryProvider).advanceStage(widget.request.id);
      ref.invalidate(requestDetailProvider(widget.request.id));
      ref.invalidate(stageProgressProvider(widget.request.id));
      ref.invalidate(requestApprovalsProvider(widget.request.id));
      messenger.showSnackBar(const SnackBar(content: Text('Moved on.')));
    } on ApiException catch (e) {
      // The refusal on a gated stage is the useful part — it says an approval
      // is now pending — so it is shown as it came rather than flattened. The
      // approval it just raised is what the list below will now show.
      ref.invalidate(stageProgressProvider(widget.request.id));
      ref.invalidate(requestApprovalsProvider(widget.request.id));
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not move it on.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(stageProgressProvider(widget.request.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Stages', icon: Icons.timeline_outlined),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not load the stages.',
            ),
            data: (progress) {
              if (progress.stages.isEmpty) {
                return Text(
                  'This request is not on a workflow, so there are no stages '
                  'to walk through. Its status is the only thing that moves.',
                  style: TextStyle(color: bos.muted, fontSize: 13, height: 1.5),
                );
              }

              final next = progress.inFlight;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.fraction,
                            minHeight: 6,
                            backgroundColor: bos.border,
                            color: bos.brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${progress.currentStage} of ${progress.totalStages}',
                        style: TextStyle(color: bos.muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final stage in progress.stages)
                    _StageRow(stage: stage),
                  _Approvals(requestId: widget.request.id),
                  if (widget.request.isOpen && next != null) ...[
                    const SizedBox(height: 12),
                    LoadingButton(
                      label: 'Finish "${next.name}"',
                      icon: Icons.check_circle_outline_rounded,
                      loading: _busy,
                      onPressed: () => _advance(next),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Sign-offs raised against this request, if any.
///
/// Deciding on one happens on the approvals screen rather than here. That is
/// where the whole queue lives, and an approver works through their queue
/// rather than hunting request by request. This only says where things stand.
class _Approvals extends ConsumerWidget {
  const _Approvals({required this.requestId});

  final int requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final approvals =
        ref.watch(requestApprovalsProvider(requestId)).value;

    // Silence is the normal case — most requests never need signing off — and
    // a failed read says nothing worth interrupting the stages for.
    if (approvals == null || approvals.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: bos.border, height: 18),
          Text(
            'Sign-offs',
            style: TextStyle(
              color: bos.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final approval in approvals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          approval.workflowStageName ?? 'A stage',
                          style: TextStyle(color: bos.text, fontSize: 13),
                        ),
                        Text(
                          [
                            if (approval.approverRole != null)
                              Fmt.label(approval.approverRole),
                            if (approval.decidedByName != null)
                              approval.decidedByName!
                            else if (approval.requestedByName != null)
                              'asked by ${approval.requestedByName}',
                            Fmt.relative(
                              approval.decidedAt ?? approval.createdAt,
                            ),
                          ].join(' · '),
                          style: TextStyle(color: bos.muted, fontSize: 11.5),
                        ),
                        if (approval.decisionNotes != null &&
                            approval.decisionNotes!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              approval.decisionNotes!,
                              style: TextStyle(
                                color: bos.muted,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(approval.status, dense: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage});

  final StageStep stage;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final (icon, colour) = stage.completed
        ? (Icons.check_circle_rounded, bos.success)
        : stage.current
            ? (Icons.radio_button_checked_rounded, bos.brand)
            : (Icons.radio_button_unchecked_rounded, bos.muted);

    final notes = <String>[
      if (stage.slaHours != null) '${stage.slaHours}h to do it',
      if (stage.requiresApproval)
        stage.approvalStatus == null
            ? 'needs approval'
            : 'approval ${stage.approvalStatus!.toLowerCase()}',
      if (stage.requiresPayment)
        stage.paymentPercent != null
            ? '${stage.paymentPercent}% due'
            : 'payment due',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.name,
                  style: TextStyle(
                    color: stage.completed ? bos.muted : bos.text,
                    fontSize: 13.5,
                    fontWeight:
                        stage.current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      notes.join(' · '),
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── The quotation ─────────────────────────────────────────────

class _Quotation extends ConsumerStatefulWidget {
  const _Quotation({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_Quotation> createState() => _QuotationState();
}

class _QuotationState extends ConsumerState<_Quotation> {
  bool _busy = false;

  Future<void> _run(
    Future<ServiceRequest> Function(RequestRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(requestRepositoryProvider));
      ref.invalidate(requestDetailProvider(widget.request.id));
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

  Future<void> _reject() async {
    final reason = await askForText(
      context,
      title: 'Why is it being turned down?',
      message: 'The person who quoted is told, so make it useful to them.',
      label: 'Reason',
      action: 'Turn it down',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _run(
      (repo) => repo.rejectQuotation(widget.request.id, reason),
      'Turned down.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final request = widget.request;
    final user = ref.watch(currentUserProvider);
    final status = request.quotationStatus;
    final quoted = request.quotationAmount != null;

    // Deciding on a quotation is CLIENT or COMPANY_OWNER — an employee may
    // quote but may not accept their own quote.
    final canDecide = status == QuotationStatus.pending &&
        (user?.hasAnyRole(const ['CLIENT', 'COMPANY_OWNER']) ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Quotation',
          icon: Icons.request_quote_outlined,
          trailing: status == null ? null : StatusChip(status, dense: true),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!quoted)
                Text(
                  'Nothing has been quoted for this request yet.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      Fmt.money(request.quotationAmount),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      request.quotationCurrency ?? '',
                      style: TextStyle(color: bos.muted, fontSize: 13),
                    ),
                  ],
                ),
                if (request.quotationValidUntil != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Good until ${Fmt.date(request.quotationValidUntil)}',
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ),
                if (request.quotationNotes != null &&
                    request.quotationNotes!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      request.quotationNotes!,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
              if (status == QuotationStatus.expired)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: MessageBanner.warning(
                    'This quotation has expired and can no longer be '
                    'accepted. Quote again to reopen it.',
                  ),
                ),
              if (canDecide) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LoadingButton(
                        label: 'Accept',
                        icon: Icons.check_rounded,
                        loading: _busy,
                        onPressed: () => _run(
                          (repo) => repo.acceptQuotation(request.id),
                          // Accepting raises an invoice, so the wording says so.
                          'Accepted. An invoice has been raised.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _reject,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Turn down'),
                      ),
                    ),
                  ],
                ),
              ],
              if (request.isOpen && status != QuotationStatus.accepted) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => showQuotationSheet(context, request: request),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(quoted ? 'Quote again' : 'Quote for this'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Quoting a price.
///
/// Always sends every field: the backend writes each one straight onto the
/// record without a null check, so a re-quote that omitted the note would
/// silently erase the old one.
Future<void> showQuotationSheet(
  BuildContext context, {
  required ServiceRequest request,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuotationSheet(request: request),
    );

class _QuotationSheet extends ConsumerStatefulWidget {
  const _QuotationSheet({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_QuotationSheet> createState() => _QuotationSheetState();
}

class _QuotationSheetState extends ConsumerState<_QuotationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: widget.request.quotationAmount?.toString() ?? '',
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.request.quotationCurrency ?? 'SAR',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.request.quotationNotes ?? '',
  );
  late DateTime? _validUntil = Fmt.parse(widget.request.quotationValidUntil);

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(requestRepositoryProvider).submitQuotation(
            widget.request.id,
            QuotationRequest(
              amount: double.parse(_amount.text.trim()),
              currency: _currency.text.trim().toUpperCase(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              // The backend wants a moment, and a quote that expires at
              // midnight the morning of its last day is not what anyone means
              // by "good until the 30th".
              validUntil: _validUntil == null
                  ? null
                  : '${Fmt.isoDate(_validUntil!)}T23:59:00',
            ),
          );
      ref.invalidate(requestDetailProvider(widget.request.id));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not send that quotation.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.request.quotationAmount == null
          ? 'Quote for this request'
          : 'Quote again',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Send the quotation',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null) return 'A figure, please.';
                  if (amount <= 0) return 'It has to be more than nothing.';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _currency,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Currency'),
                validator: (value) => (value?.trim().length ?? 0) == 3
                    ? null
                    : 'Three letters.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'Good until',
          value: _validUntil,
          firstDate: DateTime.now(),
          onChanged: (value) => setState(() => _validUntil = value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes',
            hintText: 'What the price covers, and what it does not.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sending this puts the request back to awaiting a decision and '
          'tells the client. Anything left blank here replaces what was '
          'quoted before.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}

// ── Tasks ─────────────────────────────────────────────────────

class _Tasks extends ConsumerWidget {
  const _Tasks({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestTasksProvider(request.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Tasks',
          icon: Icons.checklist_rounded,
          trailing: request.isOpen
              ? TextButton.icon(
                  onPressed: () =>
                      showTaskSheet(context, requestId: request.id),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add'),
                )
              : null,
        ),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not load the tasks.',
            ),
            data: (tasks) => tasks.isEmpty
                ? Text(
                    'Nothing has been broken out yet. Tasks are how the work '
                    'gets split up and handed round.',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  )
                : Column(
                    children: [
                      for (final task in tasks)
                        _TaskRow(
                          task: task,
                          requestId: request.id,
                          editable: request.isOpen,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({
    required this.task,
    required this.requestId,
    required this.editable,
  });

  final RequestTask task;
  final int requestId;
  final bool editable;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(RequestRepository) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(requestRepositoryProvider));
      ref.invalidate(requestTasksProvider(widget.requestId));
      ref.invalidate(requestDetailProvider(widget.requestId));
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

  Future<void> _setStatus() async {
    final status = await pickOne(
      context,
      options: [
        for (final value in TaskStatus.all)
          (value: value, label: TaskStatus.label(value)),
      ],
      current: widget.task.status,
    );
    if (status == null || status == widget.task.status || !mounted) return;
    await _run(
      (repo) => repo.updateTask(
        widget.requestId,
        widget.task.id,
        TaskRequest(status: status),
      ),
      'Marked ${TaskStatus.label(status).toLowerCase()}.',
    );
  }

  Future<void> _handOver() async {
    final person = await EmployeePicker.show(context, title: 'Who does it?');
    if (person == null || !mounted) return;
    await _run(
      (repo) => repo.updateTask(
        widget.requestId,
        widget.task.id,
        TaskRequest(assignedEmployeeId: person.id),
      ),
      'Given to ${person.fullName}.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this task?',
      message: 'It goes for good. Cancelling it instead keeps the record.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;
    await _run(
      (repo) => repo.deleteTask(widget.requestId, widget.task.id),
      'Deleted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final task = widget.task;

    final facts = <String>[
      if (task.assignedEmployeeName != null) task.assignedEmployeeName!,
      if (task.dueDate != null) 'due ${Fmt.dateShort(task.dueDate)}',
      if (task.estimatedHours != null) Fmt.hours(task.estimatedHours),
      if (task.workflowStageName != null) task.workflowStageName!,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              task.status == TaskStatus.completed
                  ? Icons.check_circle_rounded
                  : task.status == TaskStatus.blocked
                      ? Icons.report_problem_outlined
                      : Icons.circle_outlined,
              size: 17,
              color: task.status == TaskStatus.completed
                  ? bos.success
                  : task.status == TaskStatus.blocked
                      ? bos.danger
                      : bos.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    color: task.isSettled ? bos.muted : bos.text,
                    fontSize: 13.5,
                    decoration: task.status == TaskStatus.cancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (facts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      facts.join(' · '),
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (widget.editable)
            PopupMenuButton<String>(
              onSelected: (value) => switch (value) {
                'status' => _setStatus(),
                'assign' => _handOver(),
                'edit' => showTaskSheet(
                    context,
                    requestId: widget.requestId,
                    task: task,
                  ),
                _ => _delete(),
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'status', child: Text('Set status')),
                const PopupMenuItem(value: 'assign', child: Text('Hand over')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: bos.danger)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Adding a task, or changing one.
///
/// Unlike most write sheets in this app, this one may safely send only what
/// changed — `updateTask` null-checks every field.
Future<void> showTaskSheet(
  BuildContext context, {
  required int requestId,
  RequestTask? task,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskSheet(requestId: requestId, task: task),
    );

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({required this.requestId, this.task});

  final int requestId;
  final RequestTask? task;

  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.task?.description ?? '');
  late final TextEditingController _hours = TextEditingController(
    text: widget.task?.estimatedHours?.toString() ?? '',
  );
  late String _priority = widget.task?.priority ?? 'NORMAL';
  late DateTime? _dueDate = Fmt.parse(widget.task?.dueDate);

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final request = TaskRequest(
      title: _title.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      priority: _priority,
      dueDate: _dueDate == null ? null : Fmt.isoDate(_dueDate!),
      estimatedHours: double.tryParse(_hours.text.trim()),
    );

    try {
      final repo = ref.read(requestRepositoryProvider);
      if (widget.task == null) {
        await repo.addTask(widget.requestId, request);
      } else {
        await repo.updateTask(widget.requestId, widget.task!.id, request);
      }
      ref.invalidate(requestTasksProvider(widget.requestId));
      ref.invalidate(requestDetailProvider(widget.requestId));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save that task.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: widget.task == null ? 'New task' : 'Edit task',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: widget.task == null ? 'Add it' : 'Save',
      submitting: _busy,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What needs doing'),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A title, please.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Detail'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: [
            for (final value in requestPriorities)
              DropdownMenuItem(value: value, child: Text(Fmt.label(value))),
          ],
          onChanged: (value) =>
              setState(() => _priority = value ?? _priority),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Due',
                value: _dueDate,
                onChanged: (value) => setState(() => _dueDate = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _hours,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Est. hours'),
              ),
            ),
          ],
        ),
        if (widget.task != null) ...[
          const SizedBox(height: 10),
          Text(
            'Who it belongs to and what state it is in are changed from the '
            'task menu, not here.',
            style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      ],
    );
  }
}

// ── The drafted reply ─────────────────────────────────────────

/// Turns rough notes into something worth sending.
///
/// It drafts and stops. What comes back is text to read, change and post as a
/// comment yourself — nothing is sent to the client by this sheet.
Future<void> showDraftReplySheet(
  BuildContext context, {
  required int id,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DraftReplySheet(id: id),
    );

class _DraftReplySheet extends ConsumerStatefulWidget {
  const _DraftReplySheet({required this.id});

  final int id;

  @override
  ConsumerState<_DraftReplySheet> createState() => _DraftReplySheetState();
}

class _DraftReplySheetState extends ConsumerState<_DraftReplySheet> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();

  String? _draft;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _draftIt() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await ref
          .read(requestRepositoryProvider)
          .draftReply(widget.id, _notes.text.trim());
      setState(() => _draft = reply);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not draft a reply.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(requestRepositoryProvider).addComment(widget.id, _draft!);
      ref.invalidate(requestCommentsProvider(widget.id));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not post that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Draft a reply',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _draft == null ? 'Draft it' : 'Post it as a comment',
      submitting: _busy,
      onSubmit: _draft == null ? _draftIt : _post,
      children: [
        TextFormField(
          controller: _notes,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Rough notes',
            hintText: 'waiting on the licence, should be through by friday',
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'Say roughly what you want to tell them.'
              : null,
        ),
        if (_draft != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bos.bgPage,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: bos.border),
            ),
            child: SelectableText(
              _draft!,
              style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.55),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Read it before you post it. Posting adds it as a comment on the '
            'request under your name.',
            style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      ],
    );
  }
}
