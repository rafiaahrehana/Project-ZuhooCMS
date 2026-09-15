import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/attachment_launcher.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/prompts.dart';
import 'proposal_models.dart';
import 'proposal_sheet.dart';
import 'request_controllers.dart';
import 'request_repository.dart';

/// The pre-sales proposal, from both sides of it.
///
/// One card serving two different people. `ProposalServiceImpl` lets **staff**
/// write and send, and lets **the client** accept or ask for changes; neither
/// can do the other's half. So each side is offered only the buttons it can
/// actually use, rather than a row that answers 403.
///
/// A client looking at a request nobody has drafted a proposal for sees
/// nothing at all here — an empty section explaining an absence is worse than
/// no section.
class ProposalSection extends ConsumerStatefulWidget {
  const ProposalSection({super.key, required this.id, required this.isStaff});

  final int id;
  final bool isStaff;

  @override
  ConsumerState<ProposalSection> createState() => _ProposalSectionState();
}

class _ProposalSectionState extends ConsumerState<ProposalSection> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(requestProposalProvider(widget.id));
      // Sending, accepting and asking for changes all post a comment on the
      // request backend-side, so the thread below is stale the moment any of
      // them lands.
      ref.invalidate(requestCommentsProvider(widget.id));
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

  Future<void> _draft(Proposal? existing) async {
    final saved = await showProposalSheet(
      context,
      requestId: widget.id,
      existing: existing,
    );
    if (saved) ref.invalidate(requestProposalProvider(widget.id));
  }

  Future<void> _send() =>
      _run(() => ref.read(requestRepositoryProvider).sendProposal(widget.id));

  Future<void> _accept() async {
    final ok = await confirmAction(
      context,
      title: 'Accept this proposal?',
      message: 'The team will follow up with a formal quotation.',
      action: 'Accept',
      destructive: false,
    );
    if (!ok) return;
    await _run(
      () => ref.read(requestRepositoryProvider).acceptProposal(widget.id),
    );
  }

  Future<void> _requestChanges() async {
    final feedback = await askForText(
      context,
      title: 'What needs changing?',
      message:
          'This goes straight to the team. The more specific it is, the '
          'fewer rounds it takes.',
      label: 'What to change',
      action: 'Send it back',
      required: true,
    );
    if (feedback == null) return;
    await _run(
      () => ref
          .read(requestRepositoryProvider)
          .requestProposalChanges(widget.id, feedback),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestProposalProvider(widget.id));

    return async.when(
      // Neither a spinner nor an error box: this sits between two sections
      // that matter more, and having no proposal is the ordinary case.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (proposal) => proposal == null ? _empty(bos) : _card(bos, proposal),
    );
  }

  Widget _empty(BosPalette bos) {
    if (!widget.isStaff) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Proposal', icon: Icons.description_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nothing proposed yet. Draft the approach, timeline and a '
                'rough budget before quoting for it.',
                style: TextStyle(color: bos.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _draft(null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Draft a proposal'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(BosPalette bos, Proposal proposal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Proposal', icon: Icons.description_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      proposal.title,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(proposal.status, dense: true),
                ],
              ),
              if (proposal.createdByName != null) ...[
                const SizedBox(height: 3),
                Text(
                  'Drafted by ${proposal.createdByName}',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
              _line(bos, 'Tech stack', proposal.techStack),
              _line(bos, 'Timeline', proposal.timeline),
              _line(bos, 'Estimated budget', proposal.estimatedBudget),
              if (proposal.summary != null &&
                  proposal.summary!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  proposal.summary!,
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
              if (proposal.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final file in proposal.attachments)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => openAttachmentUrl(context, file.fileUrl),
                      child: Row(
                        children: [
                          Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: bos.muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              file.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bos.brandInk,
                                fontSize: 12.5,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              // Always the current round's: the backend clears the feedback on
              // every send, so it describes the version on screen and not an
              // earlier one.
              if (proposal.clientFeedback != null &&
                  proposal.clientFeedback!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                MessageBanner.warning(
                  'Client asked for changes: ${proposal.clientFeedback}',
                ),
              ],
              if (proposal.awaitsClient && widget.isStaff) ...[
                const SizedBox(height: 12),
                MessageBanner.info(
                  'Sent, and waiting on the client. It cannot be edited until '
                  'they respond.',
                ),
              ],
              ..._actions(proposal),
            ],
          ),
        ),
      ],
    );
  }

  /// The buttons this viewer can actually use, and nothing else.
  List<Widget> _actions(Proposal proposal) {
    final staffCanAct = widget.isStaff && proposal.canEdit;
    final clientCanAct = !widget.isStaff && proposal.awaitsClient;
    if (!staffCanAct && !clientCanAct) return const [];

    return [
      const SizedBox(height: 14),
      Row(
        children: [
          if (widget.isStaff) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _draft(proposal),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  proposal.status == ProposalStatus.changesRequested
                      ? 'Send revision'
                      : 'Send',
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _requestChanges,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Request changes'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _accept,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Accept'),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _line(BosPalette bos, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: bos.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
