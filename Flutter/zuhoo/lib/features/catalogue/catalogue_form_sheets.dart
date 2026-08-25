import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/form_sheet.dart';
import '../admin/admin_models.dart' show ServiceCategory;
import '../admin/admin_repository.dart' show serviceCategoriesAdminProvider;
import '../requests/request_models.dart'
    show CreateServicePackageRequest, packageBillingCycles;
import 'catalogue_models.dart';
import 'catalogue_repository.dart';

/// A category to file something under.
///
/// Reads the admin categories list, which loads itself on first watch. Two
/// callers with different needs: a service may have no category, while a
/// template must have one — `required` covers the difference.
///
/// "No category" is offered only while nothing is set. Neither update endpoint
/// can clear a category once assigned, so offering it on an edit would be a
/// control that silently does nothing.
class _CategoryField extends ConsumerWidget {
  const _CategoryField({
    required this.value,
    required this.onChanged,
    this.required = false,
    this.allowNone = true,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool required;
  final bool allowNone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(serviceCategoriesAdminProvider);
    final categories = async.value ?? const <ServiceCategory>[];

    if (categories.isEmpty) {
      // A service without a category is fine and the field simply goes away.
      // A template without one cannot be saved, so say why rather than letting
      // the save fail against the server.
      if (!required || async.isLoading) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'Add a service category in Setup first — a template has to belong '
          'to one.',
          style: TextStyle(color: bos.danger, fontSize: 12.5, height: 1.45),
        ),
      );
    }

    // A category that has been retired still labels whatever was already filed
    // under it, so it stays selectable when it is the current value.
    final options = [
      for (final category in categories)
        if (category.active || category.id == value) category,
    ];
    final offerNone = allowNone && value == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int?>(
        initialValue: options.any((c) => c.id == value) ? value : null,
        decoration: InputDecoration(
          labelText: required ? 'Category' : 'Category (optional)',
          prefixIcon: const Icon(Icons.folder_outlined),
        ),
        items: [
          if (offerNone)
            const DropdownMenuItem(value: null, child: Text('No category')),
          for (final category in options)
            DropdownMenuItem(value: category.id, child: Text(category.name)),
        ],
        onChanged: onChanged,
        validator: required && value == null ? (_) => 'Pick a category.' : null,
      ),
    );
  }
}

/// One of the service flags. A switch rather than a checkbox because each is an
/// independent setting rather than one of a set.
class _FlagSwitch extends StatelessWidget {
  const _FlagSwitch({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: TextStyle(color: bos.text, fontSize: 14)),
      subtitle: Text(hint, style: TextStyle(color: bos.muted, fontSize: 11.5)),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

// ── Services ──────────────────────────────────────────────────

Future<void> showServiceSheet(
  BuildContext context, {
  ServiceListing? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ServiceSheet(existing: existing),
  );
}

class _ServiceSheet extends ConsumerStatefulWidget {
  const _ServiceSheet({this.existing});

  final ServiceListing? existing;

  @override
  ConsumerState<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends ConsumerState<_ServiceSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.existing?.price == null ? '' : '${widget.existing!.price}',
  );
  late final TextEditingController _days = TextEditingController(
    text: widget.existing?.estimatedDays == null
        ? ''
        : '${widget.existing!.estimatedDays}',
  );

  late String _priceType = widget.existing?.priceType ?? servicePriceTypes.first;
  late int? _categoryId = widget.existing?.categoryId;

  /// Seeded from the service being edited, or all off for a new one.
  ///
  /// Held as a request object rather than nine separate fields because the
  /// request is what has to carry all nine to the server — keeping them
  /// together makes it impossible to add a tenth flag and forget to send it.
  late ServiceListingRequest _flags = widget.existing == null
      ? const ServiceListingRequest(
          name: '',
          featured: false,
          remote: false,
          onSite: false,
          online: false,
          autoApproval: false,
          requiresQuotation: false,
          requiresDocuments: false,
          supportsCustomWorkflow: false,
          aiAssisted: false,
        )
      : ServiceListingRequest.from(widget.existing!);

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _days.dispose();
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
    final repo = ref.read(catalogueRepositoryProvider);
    final request = _flags.copyWith(
      name: _name.text,
      description: _description.text,
      price: double.tryParse(_price.text.trim()),
      priceType: _priceType,
      estimatedDays: int.tryParse(_days.text.trim()),
      categoryId: _categoryId,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateService(widget.existing!.id, request);
        ref.read(servicesProvider.notifier).apply(updated);
      } else {
        await repo.createService(request);
        await ref.read(servicesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Service updated.' : 'Service added.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that service.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit service' : 'New service',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add service',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.design_services_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it covers (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        _CategoryField(
          value: _categoryId,
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'Numbers only.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _priceType,
                decoration: const InputDecoration(labelText: 'Per'),
                items: [
                  for (final type in servicePriceTypes)
                    DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
                ],
                onChanged: (value) =>
                    setState(() => _priceType = value ?? _priceType),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Typical turnaround in days (optional)',
            prefixIcon: Icon(Icons.schedule_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = int.tryParse(trimmed);
            if (parsed == null) return 'Whole days only.';
            return parsed < 0 ? 'Zero or more.' : null;
          },
        ),
        const SizedBox(height: 18),
        Text(
          'How it works',
          style: TextStyle(
            color: bos.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        // All nine are shown, and all nine are sent on save whether or not any
        // were touched. Hiding one would turn it off — see
        // [ServiceListingRequest].
        _FlagSwitch(
          label: 'Featured',
          hint: 'Shown first in the client catalogue',
          value: _flags.featured,
          onChanged: (v) => setState(() => _flags = _flags.copyWith(featured: v)),
        ),
        _FlagSwitch(
          label: 'Delivered remotely',
          hint: 'No visit needed',
          value: _flags.remote,
          onChanged: (v) => setState(() => _flags = _flags.copyWith(remote: v)),
        ),
        _FlagSwitch(
          label: 'Delivered on site',
          hint: 'Somebody attends in person',
          value: _flags.onSite,
          onChanged: (v) => setState(() => _flags = _flags.copyWith(onSite: v)),
        ),
        _FlagSwitch(
          label: 'Delivered online',
          hint: 'Handled entirely through the portal',
          value: _flags.online,
          onChanged: (v) => setState(() => _flags = _flags.copyWith(online: v)),
        ),
        _FlagSwitch(
          label: 'Approve automatically',
          hint: 'Requests start work without anyone accepting them',
          value: _flags.autoApproval,
          onChanged: (v) =>
              setState(() => _flags = _flags.copyWith(autoApproval: v)),
        ),
        _FlagSwitch(
          label: 'Needs a quotation',
          hint: 'Priced per request rather than from the catalogue',
          value: _flags.requiresQuotation,
          onChanged: (v) =>
              setState(() => _flags = _flags.copyWith(requiresQuotation: v)),
        ),
        _FlagSwitch(
          label: 'Needs documents',
          hint: 'The client must attach files before it can proceed',
          value: _flags.requiresDocuments,
          onChanged: (v) =>
              setState(() => _flags = _flags.copyWith(requiresDocuments: v)),
        ),
        _FlagSwitch(
          label: 'Custom workflow',
          hint: 'Runs its own stages instead of the default ones',
          value: _flags.supportsCustomWorkflow,
          onChanged: (v) => setState(
            () => _flags = _flags.copyWith(supportsCustomWorkflow: v),
          ),
        ),
        _FlagSwitch(
          label: 'AI assisted',
          hint: 'Drafting help is offered while the work is done',
          value: _flags.aiAssisted,
          onChanged: (v) =>
              setState(() => _flags = _flags.copyWith(aiAssisted: v)),
        ),
      ],
    );
  }
}

// ── Templates ─────────────────────────────────────────────────

Future<void> showTemplateSheet(
  BuildContext context, {
  ServiceTemplate? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TemplateSheet(existing: existing),
  );
}

class _TemplateSheet extends ConsumerStatefulWidget {
  const _TemplateSheet({this.existing});

  final ServiceTemplate? existing;

  @override
  ConsumerState<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends ConsumerState<_TemplateSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.existing?.defaultPrice == null
        ? ''
        : '${widget.existing!.defaultPrice}',
  );
  late final TextEditingController _days = TextEditingController(
    text: widget.existing?.estimatedDays == null
        ? ''
        : '${widget.existing!.estimatedDays}',
  );

  late bool _active = widget.existing?.active ?? true;
  late int? _categoryId = widget.existing?.categoryId;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _days.dispose();
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
    final repo = ref.read(catalogueRepositoryProvider);
    final request = ServiceTemplateRequest(
      name: _name.text,
      active: _active,
      description: _description.text,
      defaultPrice: double.tryParse(_price.text.trim()),
      estimatedDays: int.tryParse(_days.text.trim()),
      categoryId: _categoryId,
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateTemplate(widget.existing!.id, request);
        ref.read(templatesProvider.notifier).apply(updated);
      } else {
        await repo.createTemplate(request);
        await ref.read(templatesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Template updated.' : 'Template added.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that template.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final existing = widget.existing;

    return FormSheetFrame(
      title: _isEdit ? 'Edit template' : 'New template',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add template',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.dashboard_customize_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it is for (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        _CategoryField(
          value: _categoryId,
          required: true,
          allowNone: false,
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Default price',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'Numbers only.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null) return 'Whole days.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _FlagSwitch(
          label: 'Available',
          hint: 'Retired templates stay attached to what already uses them',
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        if (_isEdit &&
            existing != null &&
            (existing.formFieldCount > 0 ||
                existing.requiredDocumentCount > 0 ||
                existing.workflowStageCount > 0)) ...[
          const SizedBox(height: 12),
          Text(
            'Its ${existing.formFieldCount} form fields, '
            '${existing.requiredDocumentCount} required documents and '
            '${existing.workflowStageCount} workflow stages are kept as they '
            'are. Those are edited on the web.',
            style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
          ),
        ],
      ],
    );
  }
}

// ── Packages ──────────────────────────────────────────────────

/// Editing an existing package. Creating one lives on the requests screen,
/// where it was built — this is the same endpoint and the same DTO.
Future<void> showPackageEditSheet(
  BuildContext context, {
  required ServicePackage existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PackageEditSheet(existing: existing),
  );
}

class _PackageEditSheet extends ConsumerStatefulWidget {
  const _PackageEditSheet({required this.existing});

  final ServicePackage existing;

  @override
  ConsumerState<_PackageEditSheet> createState() => _PackageEditSheetState();
}

class _PackageEditSheetState extends ConsumerState<_PackageEditSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.existing.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.existing.packagePrice == null
        ? ''
        : '${widget.existing.packagePrice}',
  );
  late final TextEditingController _discount = TextEditingController(
    text: widget.existing.discountPercent == null ||
            widget.existing.discountPercent == 0
        ? ''
        : '${widget.existing.discountPercent}',
  );
  late final TextEditingController _quota = TextEditingController(
    text: widget.existing.requestQuota == null
        ? ''
        : '${widget.existing.requestQuota}',
  );
  late final TextEditingController _days = TextEditingController(
    text: widget.existing.deliveryDays == null
        ? ''
        : '${widget.existing.deliveryDays}',
  );

  late String _billingCycle = packageBillingCycles.contains(
    widget.existing.billingCycle,
  )
      ? widget.existing.billingCycle!
      : packageBillingCycles.first;

  late bool _featured = widget.existing.featured;
  late bool _popular = widget.existing.popular;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _discount.dispose();
    _quota.dispose();
    _days.dispose();
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
    // The bundled services are deliberately not sent: an empty list would be
    // read as "leave them alone" anyway, and the app has no way to pick them.
    final request = CreateServicePackageRequest(
      name: _name.text,
      billingCycle: _billingCycle,
      description: _description.text,
      packagePrice: double.tryParse(_price.text.trim()),
      discountPercent: double.tryParse(_discount.text.trim()),
      requestQuota: int.tryParse(_quota.text.trim()),
      deliveryDays: int.tryParse(_days.text.trim()),
      featured: _featured,
      popular: _popular,
    );

    try {
      final updated = await ref
          .read(catalogueRepositoryProvider)
          .updatePackage(widget.existing.id, request);
      ref.read(packagesProvider.notifier).apply(updated);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Package updated.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that package.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Edit package',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save changes',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.inventory_2_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it includes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _billingCycle,
          decoration: const InputDecoration(
            labelText: 'Billed',
            prefixIcon: Icon(Icons.event_repeat_rounded),
          ),
          items: [
            for (final cycle in packageBillingCycles)
              DropdownMenuItem(value: cycle, child: Text(Fmt.label(cycle))),
          ],
          onChanged: (value) =>
              setState(() => _billingCycle = value ?? _billingCycle),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Fixed price',
            helperText: 'Leave empty to price it from the services it bundles',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = double.tryParse(trimmed);
            if (parsed == null) return 'Numbers only.';
            return parsed < 0 ? 'Zero or more.' : null;
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _discount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Discount %',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'Numbers only.';
                  return parsed < 0 ? 'Zero or more.' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _quota,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Requests'),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null) return 'Whole number.';
                  // @Min(1): an allowance of zero is expressed by leaving it
                  // empty, which means unlimited.
                  return parsed < 1 ? 'One or more.' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Delivery days (optional)',
            prefixIcon: Icon(Icons.schedule_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = int.tryParse(trimmed);
            if (parsed == null) return 'Whole days.';
            return parsed < 0 ? 'Zero or more.' : null;
          },
        ),
        const SizedBox(height: 4),
        _FlagSwitch(
          label: 'Featured',
          hint: 'Shown first in the client catalogue',
          value: _featured,
          onChanged: (value) => setState(() => _featured = value),
        ),
        _FlagSwitch(
          label: 'Popular',
          hint: 'Marked as a common choice',
          value: _popular,
          onChanged: (value) => setState(() => _popular = value),
        ),
        if (widget.existing.packagePrice == null &&
            widget.existing.effectivePrice != null) ...[
          const SizedBox(height: 12),
          Text(
            'Currently priced at ${Fmt.money(widget.existing.effectivePrice)} '
            'from the services it bundles.',
            style: TextStyle(color: bos.muted, fontSize: 12, height: 1.45),
          ),
        ],
      ],
    );
  }
}
