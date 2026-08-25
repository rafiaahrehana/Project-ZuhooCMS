import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/form_sheet.dart';
import 'biometric_models.dart';
import 'biometric_repository.dart';

Future<void> showDeviceSheet(
  BuildContext context, {
  BiometricDevice? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DeviceSheet(existing: existing),
  );
}

class _DeviceSheet extends ConsumerStatefulWidget {
  const _DeviceSheet({this.existing});

  final BiometricDevice? existing;

  @override
  ConsumerState<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends ConsumerState<_DeviceSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.deviceName ?? '');
  late final TextEditingController _deviceId =
      TextEditingController(text: widget.existing?.deviceId ?? '');
  late final TextEditingController _ip =
      TextEditingController(text: widget.existing?.ipAddress ?? '');
  // Seeded, never left blank: a primitive int on the DTO that defaults to zero
  // when absent, so an empty box would strip the device's port.
  late final TextEditingController _port = TextEditingController(
    text: '${widget.existing?.portNumber ?? 4370}',
  );
  late final TextEditingController _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final TextEditingController _department =
      TextEditingController(text: widget.existing?.department ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late final TextEditingController _threshold = TextEditingController(
    text: '${widget.existing?.matchThreshold ?? 95}',
  );

  late String _type =
      widget.existing?.deviceType ?? biometricDeviceTypes.first;
  late bool _checkIn = widget.existing?.enabledForCheckIn ?? true;
  late bool _checkOut = widget.existing?.enabledForCheckOut ?? true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _deviceId.dispose();
    _ip.dispose();
    _port.dispose();
    _location.dispose();
    _department.dispose();
    _notes.dispose();
    _threshold.dispose();
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
    final repo = ref.read(biometricRepositoryProvider);
    final request = BiometricDeviceRequest(
      deviceName: _name.text,
      deviceType: _type,
      deviceId: _deviceId.text,
      portNumber: int.tryParse(_port.text.trim()) ?? 0,
      enabledForCheckIn: _checkIn,
      enabledForCheckOut: _checkOut,
      ipAddress: _ip.text,
      location: _location.text,
      department: _department.text,
      notes: _notes.text,
      matchThreshold: int.tryParse(_threshold.text.trim()),
    );

    try {
      if (_isEdit) {
        final updated = await repo.updateDevice(widget.existing!.id, request);
        ref.read(biometricDevicesProvider.notifier).apply(updated);
      } else {
        await repo.createDevice(request);
        await ref.read(biometricDevicesProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Terminal updated.' : 'Terminal added.')),
      );
    } on ApiException catch (e) {
      // A duplicate device identifier is refused with a message naming it.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that terminal.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: _isEdit ? 'Edit terminal' : 'New terminal',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: _isEdit ? 'Save changes' : 'Add terminal',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'What people call it — "Main entrance", "Warehouse"',
            prefixIcon: Icon(Icons.sensor_door_outlined),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A name is required.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _deviceId,
          // Not editable: the service ignores it on an update, so a changed
          // value would look saved and not be. It still has to be sent, which
          // is why the field stays rather than disappearing.
          readOnly: _isEdit,
          decoration: InputDecoration(
            labelText: 'Device identifier',
            helperText: _isEdit
                ? 'Set by the manufacturer and cannot be changed'
                : 'The serial the terminal reports as',
            prefixIcon: const Icon(Icons.qr_code_2_rounded),
            filled: _isEdit,
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'The device identifier is required.'
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Kind',
            prefixIcon: Icon(Icons.fingerprint_rounded),
          ),
          items: [
            for (final type in biometricDeviceTypes)
              DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _ip,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'IP address'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'A port.';
                  return (parsed < 0 || parsed > 65535) ? 'Out of range.' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _location,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Where it is (optional)',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _department,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Department (optional)',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _threshold,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Match threshold',
            helperText: 'How sure it has to be before it accepts somebody',
            prefixIcon: Icon(Icons.percent_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = int.tryParse(trimmed);
            if (parsed == null) return 'A number.';
            return (parsed < 1 || parsed > 100) ? 'Between 1 and 100.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _checkIn,
          onChanged: (value) => setState(() => _checkIn = value),
          title: Text(
            'Records arrivals',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: _checkOut,
          onChanged: (value) => setState(() => _checkOut = value),
          title: Text(
            'Records departures',
            style: TextStyle(color: bos.text, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!_checkIn && !_checkOut) ...[
          const SizedBox(height: 6),
          Text(
            'With both off the terminal records nothing at all.',
            style: TextStyle(color: bos.warning, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
