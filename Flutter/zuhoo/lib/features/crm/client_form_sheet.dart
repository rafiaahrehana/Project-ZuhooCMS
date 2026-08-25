import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';

Future<void> showNewClientSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewClientSheet(),
  );
}

Future<void> showEditClientSheet(BuildContext context, Client client) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditClientSheet(client: client),
  );
}

/// Shared chrome, so the two sheets below differ only in their fields.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.formKey,
    required this.error,
    required this.onDismissError,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final String? error;
  final VoidCallback onDismissError;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (error != null) ...[
                MessageBanner.error(error!, onDismiss: onDismissError),
                const SizedBox(height: 14),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Create ────────────────────────────────────────────────────

class _NewClientSheet extends ConsumerStatefulWidget {
  const _NewClientSheet();

  @override
  ConsumerState<_NewClientSheet> createState() => _NewClientSheetState();
}

class _NewClientSheetState extends ConsumerState<_NewClientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _industry = TextEditingController();
  final _website = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _company.dispose();
    _industry.dispose();
    _website.dispose();
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
      await ref.read(clientsProvider.notifier).create(
            CreateClientRequest(
              firstName: _firstName.text,
              lastName: _lastName.text,
              email: _email.text,
              phone: _phone.text,
              clientCompanyName: _company.text,
              industry: _industry.text,
              website: _website.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Client added.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add that client.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'New client',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      children: [
        TextFormField(
          controller: _firstName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return 'A first name is required.';
            // Matches the backend's @Size(min = 2) rather than letting the
            // server reject a single initial after the round trip.
            return trimmed.length < 2 ? 'At least two characters.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Last name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return 'A last name is required.';
            return trimmed.length < 2 ? 'At least two characters.' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return 'An email is required.';
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
          controller: _company,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Company (optional)',
            prefixIcon: Icon(Icons.business_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _industry,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Industry (optional)',
            prefixIcon: Icon(Icons.factory_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _website,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Website (optional)',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 12),
        // Said plainly, because "add a client" reasonably sounds like it might
        // email them, and it does not.
        const _Note(
          'This creates the client record only. Giving them a portal login is '
          'a separate step on the web.',
        ),
        const SizedBox(height: 18),
        LoadingButton(
          label: 'Add client',
          loading: _submitting,
          icon: Icons.person_add_alt_rounded,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ── Edit ──────────────────────────────────────────────────────

class _EditClientSheet extends ConsumerStatefulWidget {
  const _EditClientSheet({required this.client});

  final Client client;

  @override
  ConsumerState<_EditClientSheet> createState() => _EditClientSheetState();
}

class _EditClientSheetState extends ConsumerState<_EditClientSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _company;
  late final TextEditingController _industry;
  late final TextEditingController _website;
  late final TextEditingController _employees;
  late String _status;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    _company = TextEditingController(text: client.clientCompanyName ?? '');
    _industry = TextEditingController(text: client.industry ?? '');
    _website = TextEditingController(text: client.website ?? '');
    _employees = TextEditingController(
      text: client.employeeCount == null ? '' : '${client.employeeCount}',
    );
    _status = client.status;
  }

  @override
  void dispose() {
    _company.dispose();
    _industry.dispose();
    _website.dispose();
    _employees.dispose();
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
      await ref.read(clientsProvider.notifier).updateItem(
            widget.client.id,
            UpdateClientRequest(
              clientCompanyName: _company.text,
              industry: _industry.text,
              website: _website.text,
              status: _status,
              employeeCount: int.tryParse(_employees.text.trim()),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Client updated.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that client.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = clientStatuses.contains(_status)
        ? clientStatuses
        : [_status, ...clientStatuses];

    return _SheetFrame(
      title: 'Edit client',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      children: [
        TextFormField(
          controller: _company,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Company',
            prefixIcon: Icon(Icons.business_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _industry,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Industry',
            prefixIcon: Icon(Icons.factory_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _website,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Website',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _employees,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Employees',
            prefixIcon: Icon(Icons.groups_outlined),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return null;
            final parsed = int.tryParse(trimmed);
            if (parsed == null) return 'Enter a whole number, or leave it blank.';
            return parsed < 0 ? 'That cannot be negative.' : null;
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'Status',
            prefixIcon: Icon(Icons.toggle_on_outlined),
          ),
          items: [
            for (final status in statuses)
              DropdownMenuItem(value: status, child: Text(Fmt.label(status))),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => _status = value ?? _status),
        ),
        const SizedBox(height: 12),
        // The endpoint genuinely cannot change these, so the sheet says why
        // rather than showing fields that would silently do nothing.
        const _Note(
          'Name and email belong to the client’s own account and are not '
          'editable here.',
        ),
        const SizedBox(height: 18),
        LoadingButton(
          label: 'Save changes',
          loading: _submitting,
          icon: Icons.check_rounded,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: bos.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
