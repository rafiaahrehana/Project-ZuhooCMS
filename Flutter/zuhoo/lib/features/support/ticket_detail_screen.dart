import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/attachment_picker.dart';
import '../../shared/widgets/primitives.dart';
import 'chat_thread.dart';
import 'edit_ticket_sheet.dart';
import 'support_controllers.dart';
import 'support_models.dart';
import 'support_repository.dart';

void openTicket(BuildContext context, int id, ThreadKind kind) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TicketDetailScreen(id: id, kind: kind),
    ),
  );
}

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.id, required this.kind});

  final int id;

  /// Which conversation this is — it selects the messages endpoint and whether
  /// a reply is internal. See [ThreadKind].
  final ThreadKind kind;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final _composer = TextEditingController();
  bool _sending = false;
  bool _acting = false;

  String? _attachmentUrl;
  String? _attachmentName;
  bool _attaching = false;

  ThreadKey get _threadKey => (ticketId: widget.id, kind: widget.kind);

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final picked = await pickAttachment(context);
    if (picked == null || !mounted) return;

    setState(() {
      _attaching = true;
      _attachmentName = picked.name;
      _attachmentUrl = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final uploaded =
          await ref.read(apiClientProvider).uploadDocument(picked.path, picked.name);
      if (mounted) setState(() => _attachmentUrl = uploaded.fileUrl);
    } on ApiException catch (e) {
      if (mounted) setState(() => _attachmentName = null);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) setState(() => _attachmentName = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not upload that file.')),
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _removeAttachment() => setState(() {
        _attachmentName = null;
        _attachmentUrl = null;
      });

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || _attaching) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportRepositoryProvider).reply(
            ticketId: widget.id,
            message: text,
            // The client-chat thread is the conversation the client is reading,
            // so anything sent from it is external by construction. Internal
            // notes stay a web feature rather than a switch that can be left in
            // the wrong position.
            internal: false,
            attachmentUrl: _attachmentUrl,
            attachmentFileName: _attachmentName,
          );
      _composer.clear();
      _removeAttachment();
      ref.invalidate(ticketMessagesProvider(_threadKey));
      ref.invalidate(ticketDetailProvider(widget.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send that message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _act(
    String label,
    Future<void> Function(SupportRepository repo) action,
  ) async {
    setState(() => _acting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(supportRepositoryProvider));
      ref.invalidate(ticketDetailProvider(widget.id));
      ref.invalidate(ticketMessagesProvider(_threadKey));
      // Both lists can contain this ticket, and its status just changed in one
      // of them; refreshing whichever is alive keeps the card behind this
      // screen from lying about it.
      ref.invalidate(myTicketsProvider);
      ref.invalidate(clientTicketsProvider);
      messenger.showSnackBar(SnackBar(content: Text('$label.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not ${label.toLowerCase()} this ticket.')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _edit(SupportTicket ticket) async {
    final updated = await showEditTicketSheet(context, ticket);
    if (updated == null || !mounted) return;
    ref.invalidate(ticketDetailProvider(widget.id));
  }

  /// Removes the ticket and leaves the screen.
  Future<void> _delete(SupportTicket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${ticket.ticketNumber}?'),
        content: const Text(
          'The ticket and its whole conversation stop appearing for everyone.',
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
    if (confirmed != true || !mounted) return;

    setState(() => _acting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(supportRepositoryProvider).delete(ticket.id);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Ticket deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that ticket.')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(ticketDetailProvider(widget.id));

    // Roles, not permission codes: these two endpoints are the only ones in
    // the module gated that way.
    final user = ref.watch(currentUserProvider);
    final loaded = async.value;
    final canEdit = user?.hasAnyRole(ticketEditRoles) ?? false;
    final canDelete = user?.hasAnyRole(ticketDeleteRoles) ?? false;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(async.value?.ticketNumber ?? 'Ticket'),
        actions: [
          if (loaded != null && (canEdit || canDelete))
            _TicketMenu(
              ticket: loaded,
              canEdit: canEdit,
              canDelete: canDelete,
              enabled: !_acting,
              onEdit: _edit,
              onDelete: _delete,
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that ticket.',
          onRetry: () => ref.invalidate(ticketDetailProvider(widget.id)),
        ),
        data: (ticket) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async {
            ref.invalidate(ticketDetailProvider(widget.id));
            ref.invalidate(ticketMessagesProvider(_threadKey));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(ticket: ticket),
              const SizedBox(height: 20),
              _Facts(ticket: ticket),
              if (ticket.resolutionNotes != null &&
                  ticket.resolutionNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('Resolution',
                    icon: Icons.check_circle_outline_rounded),
                AppCard(
                  child: Text(
                    ticket.resolutionNotes!,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _Conversation(
                threadKey: _threadKey,
                composer: _composer,
                onSend: _send,
                sending: _sending,
                ticket: ticket,
                onAttach: _pickAttachment,
                attaching: _attaching,
                pendingAttachmentName: _attachmentName,
                onRemoveAttachment: _removeAttachment,
              ),
              const SizedBox(height: 20),
              _Actions(
                ticket: ticket,
                busy: _acting,
                onResolve: (notes) =>
                    _act('Resolved', (repo) => repo.resolve(ticket.id, notes)),
                onClose: () => _act('Closed', (repo) => repo.close(ticket.id)),
                onReopen: (reason) =>
                    _act('Reopened', (repo) => repo.reopen(ticket.id, reason)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

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
                  ticket.title,
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
              StatusChip(ticket.status),
            ],
          ),
          if (ticket.description != null &&
              ticket.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              ticket.description!,
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (ticket.slaBreached) ...[
            const SizedBox(height: 14),
            MessageBanner.error('This ticket is past its SLA deadline.'),
          ],
          if (ticket.isEscalated) ...[
            const SizedBox(height: 10),
            MessageBanner.info(
              'Escalated to level ${ticket.escalationLevel}'
              '${ticket.escalatedDate != null ? ' on ${Fmt.date(ticket.escalatedDate)}' : ''}.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Priority', value: Fmt.label(ticket.priority)),
      (label: 'Category', value: ticket.categoryName),
      (label: 'Raised by', value: ticket.createdByName),
      (label: 'Raised', value: Fmt.date(ticket.createdAt)),
      (label: 'Handled by', value: ticket.handlerName),
      (label: 'Source', value: ticket.source == null ? null : Fmt.label(ticket.source)),
      (
        label: 'First response due',
        value: ticket.firstResponseDeadline == null
            ? null
            : Fmt.date(ticket.firstResponseDeadline)
      ),
      (
        label: 'Resolution due',
        value: ticket.resolutionDeadline == null
            ? null
            : Fmt.date(ticket.resolutionDeadline)
      ),
      (
        label: 'Closed',
        value: ticket.closedDate == null ? null : Fmt.date(ticket.closedDate)
      ),
      (
        label: 'Satisfaction',
        value: ticket.satisfactionRating == null
            ? null
            : '${ticket.satisfactionRating}/5'
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

class _Conversation extends ConsumerWidget {
  const _Conversation({
    required this.threadKey,
    required this.composer,
    required this.onSend,
    required this.sending,
    required this.ticket,
    this.onAttach,
    this.attaching = false,
    this.pendingAttachmentName,
    this.onRemoveAttachment,
  });

  final ThreadKey threadKey;
  final TextEditingController composer;
  final VoidCallback onSend;
  final bool sending;
  final SupportTicket ticket;
  final VoidCallback? onAttach;
  final bool attaching;
  final String? pendingAttachmentName;
  final VoidCallback? onRemoveAttachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(ticketMessagesProvider(threadKey));
    final me = ref.watch(currentUserProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          threadKey.kind == ThreadKind.clientChat
              ? 'Conversation with the client'
              : 'Conversation',
          icon: Icons.forum_outlined,
        ),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 16),
            error: (error, _) => Text(
              error is ApiException
                  ? error.message
                  : 'Could not load the conversation.',
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
            data: (messages) => ChatThread(
              messages: messages,
              currentUserId: me?.id,
              controller: composer,
              onSend: onSend,
              sending: sending,
              disabled: !ticket.isOpen,
              disabledNotice: ticket.isClosed
                  ? 'This ticket is closed. Reopen it to carry on.'
                  : 'This ticket is resolved. Reopen it to carry on.',
              placeholder: threadKey.kind == ThreadKind.clientChat
                  ? 'Reply to the client'
                  : 'Write a message',
              onAttach: onAttach,
              attaching: attaching,
              pendingAttachmentName: pendingAttachmentName,
              onRemoveAttachment: onRemoveAttachment,
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.ticket,
    required this.busy,
    required this.onResolve,
    required this.onClose,
    required this.onReopen,
  });

  final SupportTicket ticket;
  final bool busy;
  final void Function(String notes) onResolve;
  final VoidCallback onClose;
  final void Function(String reason) onReopen;

  @override
  Widget build(BuildContext context) {
    if (busy) return const Loader(padding: 10);

    // Which actions exist follows from where the ticket is: an open one can be
    // resolved, a resolved one closed or reopened, a closed one only reopened.
    // Offering all three always would mean two of them erroring most of the
    // time.
    if (ticket.isClosed) {
      return OutlinedButton.icon(
        onPressed: () => _promptThen(context, _reopenPrompt, onReopen),
        icon: const Icon(Icons.lock_open_rounded, size: 18),
        label: const Text('Reopen ticket'),
      );
    }

    if (ticket.isResolved) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _promptThen(context, _reopenPrompt, onReopen),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Reopen'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Close'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _promptThen(context, _resolvePrompt, onResolve),
      icon: const Icon(Icons.task_alt_rounded, size: 18),
      label: const Text('Mark resolved'),
    );
  }

  static const _resolvePrompt = (
    title: 'Resolve this ticket',
    label: 'Resolution notes',
    hint: 'What was done, so the next person reading this knows',
    confirm: 'Resolve',
  );

  static const _reopenPrompt = (
    title: 'Reopen this ticket',
    label: 'Reason',
    hint: 'Why it needs to be looked at again',
    confirm: 'Reopen',
  );

  static Future<void> _promptThen(
    BuildContext context,
    ({String title, String label, String hint, String confirm}) prompt,
    void Function(String value) then,
  ) async {
    final result = await _askForText(context, prompt);
    if (result != null) then(result);
  }

  /// Both actions carry a required note. The backend takes them as query
  /// parameters and will accept an empty one, but a resolution with no notes is
  /// a ticket nobody can audit later.
  static Future<String?> _askForText(
    BuildContext context,
    ({String title, String label, String hint, String confirm}) prompt,
  ) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bos = Theme.of(sheetContext).bos;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    prompt.title,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    maxLines: 3,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: prompt.label,
                      hintText: prompt.hint,
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'This will be read by whoever picks the ticket up next.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(sheetContext, controller.text.trim());
                    },
                    child: Text(prompt.confirm),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }
}

/// Edit and delete, in the app bar's overflow.
///
/// A separate widget so the callbacks close over a non-nullable [SupportTicket].
class _TicketMenu extends StatelessWidget {
  const _TicketMenu({
    required this.ticket,
    required this.canEdit,
    required this.canDelete,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final SupportTicket ticket;
  final bool canEdit;
  final bool canDelete;
  final bool enabled;
  final Future<void> Function(SupportTicket) onEdit;
  final Future<void> Function(SupportTicket) onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      onSelected: (value) {
        if (value == 'edit') {
          onEdit(ticket);
        } else if (value == 'delete') {
          onDelete(ticket);
        }
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(value: 'edit', child: Text('Edit ticket')),
        if (canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
