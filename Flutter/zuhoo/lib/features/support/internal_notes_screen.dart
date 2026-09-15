import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/attachment_launcher.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/config_list.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'support_models.dart';
import 'support_queue_screen.dart';

/// What the agents said to each other about a ticket.
///
/// Its own screen rather than a filter on the conversation: internal notes are
/// never shown to the requester, and mixing them into the same thread as the
/// replies they *do* see is one misread away from an accident.
final internalNotesProvider = FutureProvider.autoDispose
    .family<List<SupportMessage>, int>(
      (ref, ticketId) =>
          ref.read(supportQueueRepositoryProvider).internalNotes(ticketId),
    );

class InternalNotesScreen extends ConsumerStatefulWidget {
  const InternalNotesScreen({super.key, required this.ticket});

  final SupportTicket ticket;

  static void open(BuildContext context, {required SupportTicket ticket}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InternalNotesScreen(ticket: ticket),
      ),
    );
  }

  @override
  ConsumerState<InternalNotesScreen> createState() =>
      _InternalNotesScreenState();
}

class _InternalNotesScreenState extends ConsumerState<InternalNotesScreen> {
  int? _busyId;

  Future<void> _edit(SupportMessage note) async {
    final text = await askForText(
      context,
      title: 'Change the note',
      message:
          'Only the wording changes. Who wrote it and when stay as they '
          'are.',
      label: 'Note',
      action: 'Save',
      required: true,
      initialValue: note.message,
    );
    if (text == null || text.trim() == note.message.trim() || !mounted) return;

    setState(() => _busyId = note.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportQueueRepositoryProvider).editMessage(note.id, text);
      ref.invalidate(internalNotesProvider(widget.ticket.id));
      messenger.showSnackBar(const SnackBar(content: Text('Changed.')));
    } on ApiException catch (e) {
      // Editing somebody else's note is refused with a message saying so.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that note.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(SupportMessage note) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this note?',
      message:
          'It goes without a trace. Only a support manager or the company '
          'owner can do this.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = note.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportQueueRepositoryProvider).deleteMessage(note.id);
      ref.invalidate(internalNotesProvider(widget.ticket.id));
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete that note.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Internal notes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.ticket.ticketNumber,
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
      body: ConfigList<SupportMessage>(
        async: ref.watch(internalNotesProvider(widget.ticket.id)),
        onRefresh: () async =>
            ref.invalidate(internalNotesProvider(widget.ticket.id)),
        emptyIcon: Icons.sticky_note_2_outlined,
        emptyTitle: 'No internal notes',
        emptyMessage:
            'Notes agents leave each other appear here. The requester never '
            'sees them. Writing one happens in the conversation, marked '
            'internal.',
        errorMessage: 'Could not load the notes.',
        itemBuilder: (context, note) => _NoteCard(
          note: note,
          busy: _busyId == note.id,
          // Anybody may try; the backend decides. Offering edit only on your
          // own notes matches the rule it enforces and saves a pointless 403.
          onEdit: note.sentById == me?.id ? () => _edit(note) : null,
          onDelete: () => _delete(note),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final SupportMessage note;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.sentByName ?? 'Somebody',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  Fmt.relative(note.createdAt),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (value) =>
                        value == 'edit' ? onEdit?.call() : onDelete?.call(),
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: bos.danger),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              note.message,
              style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.5),
            ),
            if (note.attachmentFileName != null) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => openAttachmentUrl(context, note.attachmentUrl),
                child: Row(
                  children: [
                    Icon(Icons.attach_file_rounded, size: 14, color: bos.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        note.attachmentFileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.brandInk,
                          fontSize: 11.5,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
