import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Corrects a request's title, description, priority or agreed price.
///
/// Returns the server's version, or null if dismissed.
Future<ServiceRequest?> showEditRequestSheet(
  BuildContext context,
  ServiceRequest request,
) {
  return showModalBottomSheet<ServiceRequest>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditRequestSheet(request: request),
  );
}

class _EditRequestSheet extends ConsumerStatefulWidget {
  const _EditRequestSheet({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_EditRequestSheet> createState() => _EditRequestSheetState();
}

class _EditRequestSheetState extends ConsumerState<_EditRequestSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title =
      TextEditingController(text: widget.request.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.request.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.request.agreedPrice == null
        ? ''
        : '${widget.request.agreedPrice}',
  );
  late String _priority = widget.request.priority;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
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
      final updated = await ref.read(requestRepositoryProvider).update(
            widget.request.id,
            UpdateServiceRequestRequest(
              title: _title.text,
              description: _description.text,
              priority: _priority,
              agreedPrice: double.tryParse(_price.text.trim()),
            ),
          );
      if (!mounted) return;
      navigator.pop(updated);
      messenger.showSnackBar(const SnackBar(content: Text('Request updated.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update that request.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final priorities = requestPriorities.contains(_priority)
        ? requestPriorities
        : [_priority, ...requestPriorities];

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
                'Edit request',
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
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Agreed price (optional)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null) {
                    return 'Enter a number, or leave it blank.';
                  }
                  return parsed < 0 ? 'Cannot be negative.' : null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: bos.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Moving the request along, and assigning it to somebody, '
                      'are done from the request itself — not here.',
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
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
