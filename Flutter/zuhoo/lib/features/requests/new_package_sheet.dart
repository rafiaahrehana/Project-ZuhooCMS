import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'request_controllers.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Adds a package to the company's service catalogue.
///
/// Create only. Editing and retiring a package are catalogue housekeeping that
/// stays on the web; what this is for is getting a bundle defined while it is
/// being agreed.
Future<void> showNewPackageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewPackageSheet(),
  );
}

class _NewPackageSheet extends ConsumerStatefulWidget {
  const _NewPackageSheet();

  @override
  ConsumerState<_NewPackageSheet> createState() => _NewPackageSheetState();
}

class _NewPackageSheetState extends ConsumerState<_NewPackageSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _discount = TextEditingController();
  final _quota = TextEditingController();
  final _deliveryDays = TextEditingController();

  String _billingCycle = packageBillingCycles.first;
  final Set<int> _serviceIds = {};

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _discount.dispose();
    _quota.dispose();
    _deliveryDays.dispose();
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
    try {
      await ref.read(requestRepositoryProvider).createPackage(
            CreateServicePackageRequest(
              name: _name.text,
              billingCycle: _billingCycle,
              description: _description.text,
              packagePrice: double.tryParse(_price.text.trim()),
              discountPercent: double.tryParse(_discount.text.trim()),
              requestQuota: int.tryParse(_quota.text.trim()),
              deliveryDays: int.tryParse(_deliveryDays.text.trim()),
              serviceIds: _serviceIds.toList(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} added to the catalogue.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create that package.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final services = ref.watch(catalogServicesProvider);

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
                'New package',
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
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Company formation — standard',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Name the package.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _billingCycle,
                decoration: const InputDecoration(
                  labelText: 'Billing cycle',
                  prefixIcon: Icon(Icons.event_repeat_rounded),
                ),
                items: [
                  for (final cycle in packageBillingCycles)
                    DropdownMenuItem(
                      value: cycle,
                      child: Text(Fmt.label(cycle)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) =>
                        setState(() => _billingCycle = value ?? _billingCycle),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price'),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _discount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Discount %'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null) return 'Enter a number.';
                        return parsed < 0 || parsed > 100
                            ? 'Between 0 and 100.'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quota,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Request quota'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = int.tryParse(trimmed);
                        if (parsed == null) return 'Whole number.';
                        // @Min(1): leave it blank for unlimited rather than
                        // sending a zero the backend rejects.
                        return parsed < 1 ? 'At least one.' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deliveryDays,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Delivery days'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = int.tryParse(trimmed);
                        if (parsed == null) return 'Whole number.';
                        return parsed < 0 ? 'Cannot be negative.' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              const SectionHeader(
                'Services included',
                icon: Icons.checklist_rounded,
              ),
              const SizedBox(height: 8),
              services.when(
                loading: () => const Loader(padding: 12),
                error: (_, _) => const MessageBanner.info(
                  'Could not load the catalogue. The package can be saved '
                  'without services and filled in on the web.',
                ),
                data: (available) {
                  if (available.isEmpty) {
                    return const MessageBanner.info(
                      'No active services to bundle yet.',
                    );
                  }
                  return Column(
                    children: [
                      for (final service in available)
                        CheckboxListTile(
                          value: _serviceIds.contains(service.id),
                          onChanged: _submitting
                              ? null
                              : (checked) => setState(() {
                                    if (checked ?? false) {
                                      _serviceIds.add(service.id);
                                    } else {
                                      _serviceIds.remove(service.id);
                                    }
                                  }),
                          title: Text(
                            service.name,
                            style: TextStyle(color: bos.text, fontSize: 14),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Create package',
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

  static String? _money(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a number.';
    return parsed < 0 ? 'Cannot be negative.' : null;
  }
}
