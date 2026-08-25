import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';

/// Whether this lead can still be edited at all.
///
/// The backend refuses to touch a converted or disqualified lead — "Cannot edit
/// a closed lead" — so the action is hidden rather than offered and then
/// rejected. Checked here so the detail screen and any future caller agree on
/// one answer.
bool canEditLead(Lead lead) =>
    !lead.converted && lead.status != LeadStatus.disqualified;

Future<void> showEditLeadSheet(BuildContext context, Lead lead) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditLeadSheet(lead: lead),
  );
}

class _EditLeadSheet extends ConsumerStatefulWidget {
  const _EditLeadSheet({required this.lead});

  final Lead lead;

  @override
  ConsumerState<_EditLeadSheet> createState() => _EditLeadSheetState();
}

class _EditLeadSheetState extends ConsumerState<_EditLeadSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _contactName;
  late final TextEditingController _companyName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _jobTitle;
  late final TextEditingController _value;
  late final TextEditingController _notes;

  late String _status;
  late String _source;
  late String _priority;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final lead = widget.lead;
    _contactName = TextEditingController(text: lead.contactName);
    _companyName = TextEditingController(text: lead.companyName ?? '');
    _email = TextEditingController(text: lead.email ?? '');
    _phone = TextEditingController(text: lead.phone ?? '');
    _jobTitle = TextEditingController(text: lead.jobTitle ?? '');
    _value = TextEditingController(
      text: lead.estimatedValue == null ? '' : '${lead.estimatedValue}',
    );
    _notes = TextEditingController(text: lead.notes ?? '');

    // A lead can carry a status or source this build does not know about — the
    // backend's enums can grow — and handing an unlisted value to a dropdown
    // throws. Falling back to the first known option would silently rewrite
    // the lead, so an unknown value is kept and shown as its own option below.
    _status = lead.status;
    _source = lead.source;
    _priority = lead.priority ?? 'NORMAL';
  }

  @override
  void dispose() {
    _contactName.dispose();
    _companyName.dispose();
    _email.dispose();
    _phone.dispose();
    _jobTitle.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The known options plus, if the lead is on something unrecognised, that
  /// value — so the dropdown can render its current state without inventing a
  /// change the user did not ask for.
  List<String> _optionsFor(List<String> known, String current) =>
      known.contains(current) ? known : [current, ...known];

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leadsProvider.notifier).updateItem(
            widget.lead.id,
            UpdateLeadRequest(
              contactName: _contactName.text,
              companyName: _companyName.text,
              email: _email.text,
              phone: _phone.text,
              jobTitle: _jobTitle.text,
              status: _status,
              source: _source,
              priority: _priority,
              estimatedValue: double.tryParse(_value.text.trim()),
              notes: _notes.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Lead updated.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that lead.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

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
                'Edit lead',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
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
                controller: _contactName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Who is this lead?'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Company (optional)',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  return trimmed.contains('@') ? null : 'That is not an email.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _jobTitle,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Job title (optional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.timeline_rounded),
                ),
                items: [
                  // DISQUALIFIED is offered: closing a lead out is a normal
                  // edit. The backend refuses *further* edits afterwards, which
                  // is why this sheet will not reopen for it.
                  for (final status in _optionsFor(LeadStatus.all, _status))
                    DropdownMenuItem(
                      value: status,
                      child: Text(Fmt.label(status)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  prefixIcon: Icon(Icons.input_rounded),
                ),
                items: [
                  for (final source in _optionsFor(leadSources, _source))
                    DropdownMenuItem(
                      value: source,
                      child: Text(Fmt.label(source)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _source = value ?? _source),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  for (final priority
                      in _optionsFor(leadPriorities, _priority))
                    DropdownMenuItem(
                      value: priority,
                      child: Text(Fmt.label(priority)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Estimated value (optional)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'Enter a number, or leave it blank.';
                  return parsed < 0 ? 'A deal cannot be worth less than nothing.' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
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
