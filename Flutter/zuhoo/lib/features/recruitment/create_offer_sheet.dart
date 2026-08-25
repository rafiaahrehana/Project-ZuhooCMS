import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Drafts an offer against an application.
///
/// Returns true when one was created, so the caller can refresh the offer list
/// and the application — creating an offer moves it to OFFER_PENDING.
Future<bool> showCreateOfferSheet(
  BuildContext context, {
  required int applicationId,
  String? suggestedJobTitle,
}) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CreateOfferSheet(
      applicationId: applicationId,
      suggestedJobTitle: suggestedJobTitle,
    ),
  );
  return created ?? false;
}

class _CreateOfferSheet extends ConsumerStatefulWidget {
  const _CreateOfferSheet({
    required this.applicationId,
    this.suggestedJobTitle,
  });

  final int applicationId;

  /// The posting's job title, offered as the starting point — an offer is
  /// usually for the job that was advertised.
  final String? suggestedJobTitle;

  @override
  ConsumerState<_CreateOfferSheet> createState() => _CreateOfferSheetState();
}

class _CreateOfferSheetState extends ConsumerState<_CreateOfferSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _jobTitle =
      TextEditingController(text: widget.suggestedJobTitle ?? '');
  final _gross = TextEditingController();
  final _basic = TextEditingController();
  final _houseRent = TextEditingController();
  final _medical = TextEditingController();
  final _transport = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _joiningDate;

  /// Two weeks is a common shelf life for an offer and a sensible default for
  /// a field the backend refuses to accept empty.
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 14));

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _jobTitle.dispose();
    _gross.dispose();
    _basic.dispose();
    _houseRent.dispose();
    _medical.dispose();
    _transport.dispose();
    _notes.dispose();
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
      await ref.read(recruitmentRepositoryProvider).createOffer(
            OfferRequest(
              jobApplicationId: widget.applicationId,
              offeredJobTitle: _jobTitle.text,
              expiryDate: Fmt.isoDate(_expiryDate),
              grossSalary: double.parse(_gross.text.trim()),
              joiningDate:
                  _joiningDate == null ? null : Fmt.isoDate(_joiningDate!),
              basicSalary: double.tryParse(_basic.text.trim()),
              houseRent: double.tryParse(_houseRent.text.trim()),
              medicalAllowance: double.tryParse(_medical.text.trim()),
              transportAllowance: double.tryParse(_transport.text.trim()),
              notes: _notes.text,
            ),
          );
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Offer drafted. Send it when ready.')),
      );
    } on ApiException catch (e) {
      // "This application already has an active offer" and "This application
      // is closed" both land here, and both say something worth reading.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not draft that offer.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final now = DateTime.now();

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
                'Draft an offer',
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
                controller: _jobTitle,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Offered job title',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'An offer has to name the job.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gross,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Gross salary',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'An offer has to name the money.';
                  return parsed <= 0 ? 'More than nothing.' : null;
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Offer expires',
                icon: Icons.hourglass_bottom_rounded,
                value: _expiryDate,
                enabled: !_submitting,
                firstDate: now,
                lastDate: DateTime(now.year + 2),
                // An offer with no expiry never forces a decision, and the
                // backend refuses one without it — so there is nothing to
                // clear this back to.
                clearable: false,
                onChanged: (date) {
                  if (date != null) setState(() => _expiryDate = date);
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Joining date (optional)',
                icon: Icons.flight_takeoff_rounded,
                value: _joiningDate,
                enabled: !_submitting,
                firstDate: now,
                lastDate: DateTime(now.year + 2),
                onChanged: (date) => setState(() => _joiningDate = date),
              ),
              const SizedBox(height: 22),
              const SectionHeader(
                'Breakdown',
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional. What the gross is made of, if it has been agreed.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _basic,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Basic'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _houseRent,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'House rent'),
                      validator: _money,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _medical,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Medical'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _transport,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Transport'),
                      validator: _money,
                    ),
                  ),
                ],
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
                label: 'Draft offer',
                loading: _submitting,
                icon: Icons.description_outlined,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _money(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a number.';
    return parsed < 0 ? 'Cannot be negative.' : null;
  }
}
