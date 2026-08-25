import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/primitives.dart';
import 'itam_models.dart';
import 'itam_repository.dart';

/// Adds a machine to the register.
Future<void> showNewAssetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AssetFormSheet(),
  );
}

/// Edits one, and hands back the server's version of it.
///
/// Returns null when the sheet is dismissed without saving. The detail screen
/// holds its own copy of the asset rather than watching a provider, so it needs
/// the updated record back to stay in step with the list behind it.
Future<Asset?> showEditAssetSheet(BuildContext context, Asset asset) {
  return showModalBottomSheet<Asset>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssetFormSheet(existing: asset),
  );
}

class _AssetFormSheet extends ConsumerStatefulWidget {
  const _AssetFormSheet({this.existing});

  final Asset? existing;

  @override
  ConsumerState<_AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends ConsumerState<_AssetFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _assetTag;
  late final TextEditingController _serialNumber;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _os;
  late final TextEditingController _processor;
  late final TextEditingController _ram;
  late final TextEditingController _storage;
  late final TextEditingController _ip;
  late final TextEditingController _mac;
  late final TextEditingController _notes;

  DateTime? _purchaseDate;
  DateTime? _warrantyExpiry;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final asset = widget.existing;
    _name = TextEditingController(text: asset?.name ?? '');
    _category = TextEditingController(text: asset?.category ?? '');
    _assetTag = TextEditingController(text: asset?.assetTag ?? '');
    _serialNumber = TextEditingController(text: asset?.serialNumber ?? '');
    _brand = TextEditingController(text: asset?.brand ?? '');
    _model = TextEditingController(text: asset?.model ?? '');
    _os = TextEditingController(text: asset?.operatingSystem ?? '');
    _processor = TextEditingController(text: asset?.processorModel ?? '');
    _ram = TextEditingController(text: asset?.ramSize ?? '');
    _storage = TextEditingController(text: asset?.storageSize ?? '');
    _ip = TextEditingController(text: asset?.ipAddress ?? '');
    _mac = TextEditingController(text: asset?.macAddress ?? '');
    _notes = TextEditingController(text: asset?.notes ?? '');
    _purchaseDate = Fmt.parse(asset?.purchaseDate);
    _warrantyExpiry = Fmt.parse(asset?.warrantyExpiry);
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _assetTag.dispose();
    _serialNumber.dispose();
    _brand.dispose();
    _model.dispose();
    _os.dispose();
    _processor.dispose();
    _ram.dispose();
    _storage.dispose();
    _ip.dispose();
    _mac.dispose();
    _notes.dispose();
    super.dispose();
  }

  AssetRequest _buildRequest() => AssetRequest(
        name: _name.text,
        category: _category.text,
        assetTag: _assetTag.text,
        serialNumber: _serialNumber.text,
        brand: _brand.text,
        model: _model.text,
        purchaseDate:
            _purchaseDate == null ? null : Fmt.isoDate(_purchaseDate!),
        warrantyExpiry:
            _warrantyExpiry == null ? null : Fmt.isoDate(_warrantyExpiry!),
        operatingSystem: _os.text,
        processorModel: _processor.text,
        ramSize: _ram.text,
        storageSize: _storage.text,
        ipAddress: _ip.text,
        macAddress: _mac.text,
        notes: _notes.text,
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
    final navigator = Navigator.of(context);
    final controller = ref.read(assetsProvider.notifier);
    try {
      if (_isEdit) {
        final updated =
            await controller.updateItem(widget.existing!.id, _buildRequest());
        if (!mounted) return;
        navigator.pop(updated);
        messenger.showSnackBar(const SnackBar(content: Text('Asset updated.')));
      } else {
        await controller.create(_buildRequest());
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Asset added to the register.')),
        );
      }
    } on ApiException catch (e) {
      // Duplicate serial number and duplicate asset tag both land here with a
      // message that names which one clashed, so it is shown as written.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            _isEdit ? 'Could not save that asset.' : 'Could not add that asset.');
      }
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
                _isEdit ? 'Edit asset' : 'New asset',
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
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'MacBook Pro 14"',
                  prefixIcon: Icon(Icons.devices_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'What is this machine?'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  hintText: 'Laptop, Monitor, Phone…',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _assetTag,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Asset tag (optional)',
                  prefixIcon: Icon(Icons.qr_code_2_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serialNumber,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Serial number (optional)',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Brand (optional)',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(
                  labelText: 'Model (optional)',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Purchased (optional)',
                value: _purchaseDate,
                enabled: !_submitting,
                // Hardware is bought in the past; nothing was bought tomorrow.
                firstDate: DateTime(DateTime.now().year - 20),
                lastDate: DateTime.now(),
                onChanged: (date) => setState(() => _purchaseDate = date),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Warranty expires (optional)',
                icon: Icons.verified_user_outlined,
                value: _warrantyExpiry,
                enabled: !_submitting,
                // A warranty usually runs forward, but an expired one is worth
                // being able to record, so this reaches back a year too.
                firstDate: DateTime(DateTime.now().year - 1),
                lastDate: DateTime(DateTime.now().year + 15),
                onChanged: (date) => setState(() => _warrantyExpiry = date),
              ),
              const SizedBox(height: 22),
              const SectionHeader('Specification', icon: Icons.memory_rounded),
              const SizedBox(height: 12),
              TextFormField(
                controller: _os,
                decoration: const InputDecoration(
                  labelText: 'Operating system (optional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _processor,
                decoration: const InputDecoration(
                  labelText: 'Processor (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ram,
                      decoration: const InputDecoration(labelText: 'RAM'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _storage,
                      decoration: const InputDecoration(labelText: 'Storage'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ip,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'IP address (optional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mac,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'MAC address (optional)',
                ),
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
                label: _isEdit ? 'Save changes' : 'Add asset',
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
