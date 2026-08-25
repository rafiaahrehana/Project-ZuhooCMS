import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import 'itam_models.dart';
import 'itam_repository.dart';

/// Registers a software licence.
///
/// Create only. Editing one is `PUT /v1/itam/software/{id}`, which the app
/// does not offer yet — what it does offer is handing seats out, which is the
/// part that happens away from a desk.
Future<void> showNewLicenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LicenseFormSheet(),
  );
}

class _LicenseFormSheet extends ConsumerStatefulWidget {
  const _LicenseFormSheet();

  @override
  ConsumerState<_LicenseFormSheet> createState() => _LicenseFormSheetState();
}

class _LicenseFormSheetState extends ConsumerState<_LicenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _softwareName = TextEditingController();
  final _publisher = TextEditingController();
  final _licenseKey = TextEditingController();
  final _version = TextEditingController();
  final _seats = TextEditingController(text: '1');
  final _cost = TextEditingController();
  final _renewalCost = TextEditingController();

  String _licenseType = licenseTypes.first.value;
  String _renewalType = licenseRenewalTypes.first.value;
  late DateTime _purchaseDate = DateTime.now();
  late DateTime _expiryDate = DateTime(
    DateTime.now().year + 1,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime? _nextRenewal;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _softwareName.dispose();
    _publisher.dispose();
    _licenseKey.dispose();
    _version.dispose();
    _seats.dispose();
    _cost.dispose();
    _renewalCost.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_expiryDate.isBefore(_purchaseDate)) {
      setState(() => _error = 'The licence expires before it was bought.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(licensesProvider.notifier).create(
            SoftwareLicenseRequest(
              licenseKey: _licenseKey.text,
              softwareName: _softwareName.text,
              publisher: _publisher.text,
              licenseType: _licenseType,
              totalSeatsLicensed: int.parse(_seats.text.trim()),
              licensePurchaseDate: Fmt.isoDate(_purchaseDate),
              licenseExpiryDate: Fmt.isoDate(_expiryDate),
              licenseCost: double.parse(_cost.text.trim()),
              renewalType: _renewalType,
              version: _version.text,
              nextRenewalDate:
                  _nextRenewal == null ? null : Fmt.isoDate(_nextRenewal!),
              renewalCost: double.tryParse(_renewalCost.text.trim()),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${_softwareName.text.trim()} licence registered.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not register that licence.');
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
                'New licence',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The backend asks for most of this, so there is little here to '
                'skip.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
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
                controller: _softwareName,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Software',
                  hintText: 'Figma',
                  prefixIcon: Icon(Icons.apps_rounded),
                ),
                validator: _required('Name the software.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _publisher,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Publisher',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                validator: _required('Who publishes it?'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _licenseKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Licence key',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'The licence key is required.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _version,
                decoration: const InputDecoration(
                  labelText: 'Version (optional)',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _licenseType,
                decoration: const InputDecoration(
                  labelText: 'Licence type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  for (final type in licenseTypes)
                    DropdownMenuItem(
                      value: type.value,
                      child: Text(type.label),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) =>
                        setState(() => _licenseType = value ?? _licenseType),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _seats,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seats bought',
                  prefixIcon: Icon(Icons.event_seat_outlined),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter a whole number of seats.';
                  // @Min(1): a licence with no seats is not a licence.
                  return parsed < 1 ? 'At least one seat.' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cost',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'What did it cost?';
                  return parsed < 0 ? 'Cannot be negative.' : null;
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Bought on',
                value: _purchaseDate,
                enabled: !_submitting,
                clearable: false,
                firstDate: DateTime(now.year - 15),
                lastDate: now,
                onChanged: (date) {
                  if (date != null) setState(() => _purchaseDate = date);
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Expires on',
                icon: Icons.hourglass_bottom_rounded,
                value: _expiryDate,
                enabled: !_submitting,
                clearable: false,
                firstDate: DateTime(now.year - 15),
                lastDate: DateTime(now.year + 20),
                onChanged: (date) {
                  if (date != null) setState(() => _expiryDate = date);
                },
              ),
              const SizedBox(height: 22),
              const SectionHeader('Renewal', icon: Icons.autorenew_rounded),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _renewalType,
                decoration: const InputDecoration(labelText: 'Renews'),
                items: [
                  for (final type in licenseRenewalTypes)
                    DropdownMenuItem(
                      value: type.value,
                      child: Text(type.label),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) =>
                        setState(() => _renewalType = value ?? _renewalType),
              ),
              if (_renewalType != 'PERPETUAL') ...[
                const SizedBox(height: 16),
                DateField(
                  label: 'Next renewal (optional)',
                  value: _nextRenewal,
                  enabled: !_submitting,
                  firstDate: now,
                  lastDate: DateTime(now.year + 20),
                  onChanged: (date) => setState(() => _nextRenewal = date),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _renewalCost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Renewal cost (optional)',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return null;
                    final parsed = double.tryParse(trimmed);
                    if (parsed == null) return 'Enter a number.';
                    return parsed < 0 ? 'Cannot be negative.' : null;
                  },
                ),
              ],
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Register licence',
                loading: _submitting,
                icon: Icons.add_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? Function(String?) _required(String message) =>
      (value) => (value == null || value.trim().isEmpty) ? message : null;
}
