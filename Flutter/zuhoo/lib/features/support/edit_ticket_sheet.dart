import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'support_models.dart';
import 'support_repository.dart';

/// Corrects a ticket. Returns the server's version, or null if dismissed.
Future<SupportTicket?> showEditTicketSheet(
  BuildContext context,
  SupportTicket ticket,
) {
  return showModalBottomSheet<SupportTicket>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditTicketSheet(ticket: ticket),
  );
}

class _EditTicketSheet extends ConsumerStatefulWidget {
  const _EditTicketSheet({required this.ticket});

  final SupportTicket ticket;

  @override
  ConsumerState<_EditTicketSheet> createState() => _EditTicketSheetState();
}

class _EditTicketSheetState extends ConsumerState<_EditTicketSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title =
      TextEditingController(text: widget.ticket.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.ticket.description ?? '');
  late String _priority = widget.ticket.priority;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
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
    final navigator = Navigator.of(context);
    try {
      final updated =
          await ref.read(supportRepositoryProvider).update(
                widget.ticket.id,
                UpdateTicketRequest(
                  title: _title.text,
                  description: _description.text,
                  priority: _priority,
                ),
              );
      if (!mounted) return;
      navigator.pop(updated);
      messenger.showSnackBar(const SnackBar(content: Text('Ticket updated.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update that ticket.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final priorities = ticketPriorities.contains(_priority)
        ? ticketPriorities
        : [_priority, ...ticketPriorities];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit ticket',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.ticket.ticketNumber,
                style: TextStyle(color: bos.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A title is required.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
                // Required server-side too, and sent unconditionally — an
                // emptied box would blank the ticket rather than be ignored.
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A description is required.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  for (final priority in priorities)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(Fmt.label(priority)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Save changes',
                loading: _submitting,
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
