import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/chat/live_message_buffer.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/attachment_launcher.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/timeline.dart';
import 'edit_request_sheet.dart';
import 'rate_request_sheet.dart';
import 'request_controllers.dart';
import 'proposal_section.dart';
import 'request_models.dart';
import 'request_repository.dart';
import 'request_workflow_screen.dart';

/// Opens one request. Pushed rather than routed by path so the list it came
/// from stays exactly where it was, scroll position included.
void openRequestDetail(BuildContext context, int id) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => RequestDetailScreen(id: id)));
}

class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestDetailProvider(id));
    final loaded = async.value;

    // Any one of assign / approve / close will do — that is what the service
    // checks. A closed request is refused outright, so the action goes away.
    final canRate =
        loaded != null &&
        loaded.status == RequestStatus.completed &&
        (ref.watch(currentUserProvider)?.isClient ?? false);

    final isStaff =
        loaded != null && !(ref.watch(currentUserProvider)?.isClient ?? false);

    final canEdit =
        loaded != null &&
        loaded.isOpen &&
        ref
            .watch(permissionControllerProvider)
            .hasAny(RequestPermissions.editAny);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Request'),
        actions: [
          // Staff only. The workflow endpoints behind it are all
          // hasAnyRole('COMPANY_OWNER', 'EMPLOYEE'), so a client who reached
          // this screen would only find a wall of refusals.
          if (isStaff)
            IconButton(
              tooltip: 'Working on it',
              icon: const Icon(Icons.build_outlined),
              onPressed: () => RequestWorkflowScreen.open(context, id: id),
            ),
          // A client rating their own finished request. Staff never see it:
          // the endpoint is hasRole('CLIENT'), and rating on somebody's behalf
          // is not a thing.
          if (canRate)
            IconButton(
              tooltip: 'Rate this',
              icon: const Icon(Icons.star_border_rounded),
              onPressed: () => showRateRequestSheet(context, request: loaded),
            ),
          if (canEdit)
            IconButton(
              tooltip: 'Edit request',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await showEditRequestSheet(context, loaded);
                if (updated != null) ref.invalidate(requestDetailProvider(id));
              },
            ),
          if (async.value?.canCancel ?? false)
            IconButton(
              tooltip: 'Withdraw',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _withdraw(context, ref, async.value!),
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
            ref.invalidate(requestDocumentsProvider(id));
            ref.invalidate(requestCommentsProvider(id));
            ref.invalidate(requestHistoryProvider(id));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(request: request),
              const SizedBox(height: 20),
              _Facts(request: request),
              if (request.description != null &&
                  request.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('Description', icon: Icons.notes_rounded),
                AppCard(
                  child: Text(
                    request.description!,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              // Ahead of the quotation, because that is the order the two
              // happen in: staff propose an approach, the client accepts it,
              // and only then does a binding quotation follow.
              const SizedBox(height: 20),
              ProposalSection(id: id, isStaff: isStaff),
              if (request.hasQuotation) ...[
                const SizedBox(height: 20),
                _Quotation(request: request),
              ],
              const SizedBox(height: 20),
              _Documents(id: id),
              const SizedBox(height: 20),
              _Comments(id: id),
              const SizedBox(height: 20),
              _Timeline(id: id),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    ServiceRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text('"${request.title}" will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(myRequestsProvider.notifier).cancel(request.id);
      ref.invalidate(requestDetailProvider(request.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Request withdrawn.')),
      );
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final progress = request.taskProgress;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request.title,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(request.status),
            ],
          ),
          if (request.hubServiceName != null) ...[
            const SizedBox(height: 6),
            Text(
              request.hubServiceName!,
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
          ],
          if (request.slaBreach) ...[
            const SizedBox(height: 14),
            MessageBanner.error('This request is past its SLA deadline.'),
          ],
          if (progress != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Tasks',
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${request.completedTaskCount} of ${request.taskCount} done',
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: bos.neutralSoft,
                valueColor: AlwaysStoppedAnimation(bos.brand),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Priority', value: Fmt.label(request.priority)),
      (label: 'Raised', value: Fmt.date(request.createdAt)),
      (
        label: 'SLA deadline',
        value: request.slaDeadline == null
            ? null
            : Fmt.date(request.slaDeadline),
      ),
      (label: 'Assigned to', value: request.assignedEmployeeName),
      (
        label: 'Assigned',
        value: request.assignedAt == null ? null : Fmt.date(request.assignedAt),
      ),
      (label: 'Client', value: request.clientName),
      (label: 'Package', value: request.packageName),
      (
        label: 'Agreed price',
        value: request.agreedPrice == null
            ? null
            : Fmt.money(request.agreedPrice),
      ),
      (
        label: 'Filing reference',
        value: request.govRefNumber == null
            ? null
            : '${request.govRefNumber}'
                  '${request.govRefType != null ? ' (${Fmt.label(request.govRefType)})' : ''}',
      ),
      (
        label: 'Completed',
        value: request.completedAt == null
            ? null
            : Fmt.date(request.completedAt),
      ),
      (
        label: 'Resubmitted',
        value: request.resubmitCount > 0 ? '${request.resubmitCount}×' : null,
      ),
    ].where((row) => row.value != null && row.value!.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Details', icon: Icons.info_outline_rounded),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: bos.borderLight),
                  const SizedBox(height: 10),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rows[i].value!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The quotation lives on the request itself. Read-only here: accepting or
/// rejecting one creates an invoice and starts a payment, which belongs with
/// the billing flow rather than bolted onto a detail screen.
class _Quotation extends StatelessWidget {
  const _Quotation({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Quotation', icon: Icons.request_quote_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(request.quotationAmount),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(request.quotationStatus ?? 'PENDING', dense: true),
                ],
              ),
              if (request.quotationValidUntil != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Valid until ${Fmt.date(request.quotationValidUntil)}',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ],
              if (request.quotationNotes != null &&
                  request.quotationNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  request.quotationNotes!,
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
              if (request.quotationAwaitsDecision) ...[
                const SizedBox(height: 12),
                MessageBanner.info(
                  'Accepting or declining this quotation raises an invoice, so '
                  'it is done from the web app for now.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Documents extends ConsumerStatefulWidget {
  const _Documents({required this.id});

  final int id;

  @override
  ConsumerState<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends ConsumerState<_Documents> {
  bool _uploading = false;

  Future<void> _add() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uploaded = await ref
          .read(apiClientProvider)
          .uploadDocument(picked.path, picked.name);
      await ref
          .read(requestRepositoryProvider)
          .addDocument(
            widget.id,
            fileName: uploaded.fileName,
            fileUrl: uploaded.fileUrl,
          );
      ref.invalidate(requestDocumentsProvider(widget.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not attach that document.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestDocumentsProvider(widget.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Documents',
          icon: Icons.attach_file_rounded,
          trailing: _uploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(onPressed: _add, child: const Text('Add')),
        ),
        async.when(
          loading: () => const AppCard(child: Loader(padding: 8)),
          error: (_, _) => const AppCard(
            child: MessageBanner.info('Could not load the documents.'),
          ),
          data: (documents) {
            if (documents.isEmpty) {
              return const AppCard(
                child: MessageBanner.info('No documents attached yet.'),
              );
            }
            return AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < documents.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: bos.borderLight),
                    ListTile(
                      leading: Icon(
                        Icons.description_outlined,
                        color: bos.textSecondary,
                      ),
                      title: Text(
                        documents[i].fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: documents[i].uploadedByName == null
                          ? null
                          : Text(
                              'by ${documents[i].uploadedByName}',
                              style: TextStyle(
                                color: bos.muted,
                                fontSize: 11.5,
                              ),
                            ),
                      onTap: () =>
                          openAttachmentUrl(context, documents[i].fileUrl),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.id});

  final int id;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _controller = TextEditingController();
  bool _sending = false;

  final _live = LiveMessageBuffer<RequestComment>(
    idOf: (c) => c.id,
    createdAtOf: (c) => c.createdAt,
  );
  void Function()? _unsubscribeChat;

  @override
  void initState() {
    super.initState();
    // Mirrors Angular's request-detail.ts connectLive(). The backend only
    // pushes a CLIENT-visibility comment to the other side of the
    // conversation (ServiceRequestServiceImpl) — an internal-only comment
    // never arrives here, same split as the ticket screens.
    _unsubscribeChat = connectLiveMessages<RequestComment>(
      socket: ref.read(chatSocketServiceProvider),
      destination: '/user/queue/service-requests/${widget.id}/messages',
      fromJson: RequestComment.fromJson,
      buffer: _live,
      onMessage: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _unsubscribeChat?.call();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(requestRepositoryProvider).addComment(widget.id, text);
      _controller.clear();
      ref.invalidate(requestCommentsProvider(widget.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not post that comment.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestCommentsProvider(widget.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Comments', icon: Icons.forum_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              async.when(
                loading: () => const Loader(padding: 12),
                error: (_, _) => Text(
                  'Could not load the conversation.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
                data: (fetched) {
                  final comments = _live.merge(fetched);
                  if (comments.isEmpty) {
                    return Text(
                      'No comments yet.',
                      style: TextStyle(color: bos.muted, fontSize: 13.5),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < comments.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _Comment(comment: comments[i]),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: bos.borderLight),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a comment',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: bos.brand),
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({required this.comment});

  final RequestComment comment;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(initials: _initials(comment.authorName), size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.authorName ?? 'Someone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Fmt.relative(comment.createdAt),
                    style: TextStyle(color: bos.muted, fontSize: 11),
                  ),
                  // An internal note is staff-only. Labelling it is what stops
                  // someone reading it aloud to a client on a call.
                  if (comment.isInternal) ...[
                    const SizedBox(width: 8),
                    const StatusChip(
                      'INTERNAL',
                      label: 'Internal',
                      dense: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                comment.content,
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestHistoryProvider(id));
    final history = async.value;

    // Absent history is not an error worth a panel: an employee without the
    // permission to read it simply does not get this section.
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History', icon: Icons.history_rounded),
        AppCard(
          child: Timeline(
            railColor: bos.border,
            tiles: [
              for (final change in history)
                TimelineTile(
                  dotColor: bos.statusColors(change.newStatus).fg,
                  child: _StatusChangeContent(change: change),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChangeContent extends StatelessWidget {
  const _StatusChangeContent({required this.change});

  final RequestStatusChange change;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                change.oldStatus == null
                    ? Fmt.label(change.newStatus)
                    : '${Fmt.label(change.oldStatus)} → ${Fmt.label(change.newStatus)}',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              Fmt.relative(change.changedAt),
              style: TextStyle(color: bos.muted, fontSize: 11),
            ),
          ],
        ),
        if (change.changedByName != null) ...[
          const SizedBox(height: 2),
          Text(
            'by ${change.changedByName}',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
        ],
        if (change.reason != null && change.reason!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            change.reason!,
            style: TextStyle(
              color: bos.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}
