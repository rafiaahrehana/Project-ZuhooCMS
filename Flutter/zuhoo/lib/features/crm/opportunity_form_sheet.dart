import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';

/// Opening a deal always starts from a client.
///
/// `OpportunityServiceImpl` requires a `clientId` on the direct-create path —
/// only the lead-conversion route may leave it null — so the sheet is reached
/// from a client rather than from the pipeline. That also spares the phone a
/// searchable client picker over a paginated list to answer a question the
/// caller already knows the answer to.
Future<void> showNewOpportunitySheet(
  BuildContext context, {
  required int clientId,
  required String clientName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OpportunityFormSheet(
      clientId: clientId,
      clientName: clientName,
    ),
  );
}

Future<void> showEditOpportunitySheet(
  BuildContext context,
  Opportunity opportunity,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OpportunityFormSheet(existing: opportunity),
  );
}

class _OpportunityFormSheet extends ConsumerStatefulWidget {
  const _OpportunityFormSheet({
    this.existing,
    this.clientId,
    this.clientName,
  });

  /// Null when opening a new deal.
  final Opportunity? existing;

  final int? clientId;
  final String? clientName;

  @override
  ConsumerState<_OpportunityFormSheet> createState() =>
      _OpportunityFormSheetState();
}

class _OpportunityFormSheetState extends ConsumerState<_OpportunityFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _nextStep;

  DateTime? _expectedClose;
  String? _source;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _amount = TextEditingController(
      text: existing?.amount == null ? '' : '${existing!.amount}',
    );
    // Seeded even when empty: the backend assigns these two unconditionally on
    // update, so whatever is in these fields at submit time is what the deal
    // ends up with. See OpportunityRequest for the full story.
    _description = TextEditingController(text: existing?.description ?? '');
    _nextStep = TextEditingController(text: existing?.nextStep ?? '');
    _expectedClose = Fmt.parse(existing?.expectedCloseDate);
    _source = existing?.source;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _description.dispose();
    _nextStep.dispose();
    super.dispose();
  }

  Future<void> _pickCloseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedClose ?? now,
      // A deal can be expected to close in the past — a slipped date is a real
      // state worth being able to record and correct — so this reaches back a
      // year as well as forward.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expectedClose = picked);
  }

  OpportunityRequest _buildRequest() => OpportunityRequest(
        name: _name.text,
        description: _description.text,
        nextStep: _nextStep.text,
        // Only sent on create; the update path ignores it.
        clientId: _isEdit ? null : widget.clientId,
        amount: double.tryParse(_amount.text.trim()),
        expectedCloseDate:
            _expectedClose == null ? null : Fmt.isoDate(_expectedClose!),
        source: _source,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(opportunitiesProvider.notifier);
    try {
      if (_isEdit) {
        await controller.updateItem(widget.existing!.id, _buildRequest());
      } else {
        await controller.create(_buildRequest());
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Deal updated.' : 'Deal opened.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _isEdit
            ? 'Could not save that deal.'
            : 'Could not open that deal.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final sources = _source == null || leadSources.contains(_source)
        ? leadSources
        : [_source!, ...leadSources];

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
                _isEdit ? 'Edit deal' : 'New deal',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!_isEdit && widget.clientName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'For ${widget.clientName}',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _name,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Deal name',
                  hintText: 'Annual licence renewal',
                  prefixIcon: Icon(Icons.handshake_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give the deal a name.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (optional)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) {
                    return 'Enter a number, or leave it blank.';
                  }
                  return parsed < 0
                      ? 'A deal cannot be worth less than nothing.'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _submitting ? null : _pickCloseDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Expected close (optional)',
                    prefixIcon: const Icon(Icons.event_outlined),
                    suffixIcon: _expectedClose == null
                        ? null
                        : IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: bos.muted,
                            ),
                            tooltip: 'Clear',
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _expectedClose = null),
                          ),
                  ),
                  child: Text(
                    _expectedClose == null
                        ? 'Not set'
                        : Fmt.date(Fmt.isoDate(_expectedClose!)),
                    style: TextStyle(
                      color: _expectedClose == null ? bos.muted : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(
                  labelText: 'Source (optional)',
                  prefixIcon: Icon(Icons.input_rounded),
                ),
                items: [
                  for (final source in sources)
                    DropdownMenuItem(
                      value: source,
                      child: Text(Fmt.label(source)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _source = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nextStep,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Next step',
                  hintText: 'Send the revised quote',
                  prefixIcon: Icon(Icons.arrow_forward_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: bos.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Moving the deal to another stage is done from the '
                        'deal itself, not here.',
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
              const SizedBox(height: 18),
              LoadingButton(
                label: _isEdit ? 'Save changes' : 'Open deal',
                loading: _submitting,
                icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
