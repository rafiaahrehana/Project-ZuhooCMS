import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/date_field.dart';
import '../../shared/widgets/form_sheet.dart';
import '../finance/finance_models.dart' show CreateExpenseRequest;
import 'platform_expenses_tab.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

// ── The platform's own expenses ───────────────────────────────

/// Files an expense against the platform's books.
///
/// The same DTO as a company expense, so the request model comes from the
/// finance module. Editing is not offered — see the note at the top of
/// [PlatformExpensesTab] for why.
Future<void> showPlatformExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PlatformExpenseSheet(),
  );
}

class _PlatformExpenseSheet extends ConsumerStatefulWidget {
  const _PlatformExpenseSheet();

  @override
  ConsumerState<_PlatformExpenseSheet> createState() =>
      _PlatformExpenseSheetState();
}

class _PlatformExpenseSheetState extends ConsumerState<_PlatformExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _vendor.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final date = _date;
    if (date == null) {
      setState(() => _error = 'Pick the date it was spent.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(platformRepositoryProvider).createPlatformExpense(
            CreateExpenseRequest(
              description: _description.text,
              amount: double.parse(_amount.text.trim()),
              expenseDate: Fmt.isoDate(date),
              vendorName: _vendor.text,
              category: _category.text,
              notes: _notes.text,
            ),
          );
      await ref.read(platformExpensesProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Expense filed.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not file that expense.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetFrame(
      title: 'New platform expense',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'File it',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _description,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it was for',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'Say what the money went on.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          validator: (value) {
            final parsed = double.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'An amount is required.';
            return parsed <= 0 ? 'More than zero.' : null;
          },
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Spent on',
          value: _date,
          clearable: false,
          lastDate: DateTime.now(),
          onChanged: (value) => setState(() => _date = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _vendor,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Paid to (optional)',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _category,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category (optional)',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
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
      ],
    );
  }
}

// ── Editing platform staff ────────────────────────────────────

/// Changes a member of platform staff.
///
/// Name, email and role are all required by the update — the backend checks
/// each by hand and refuses a blank one — so the form seeds them and validates
/// them here rather than letting the call fail.
Future<void> showEditPlatformUserSheet(
  BuildContext context, {
  required PlatformUser user,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditPlatformUserSheet(user: user),
  );
}

class _EditPlatformUserSheet extends ConsumerStatefulWidget {
  const _EditPlatformUserSheet({required this.user});

  final PlatformUser user;

  @override
  ConsumerState<_EditPlatformUserSheet> createState() =>
      _EditPlatformUserSheetState();
}

class _EditPlatformUserSheetState
    extends ConsumerState<_EditPlatformUserSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName =
      TextEditingController(text: widget.user.firstName);
  late final TextEditingController _lastName =
      TextEditingController(text: widget.user.lastName);
  late final TextEditingController _email =
      TextEditingController(text: widget.user.email);
  late final TextEditingController _phone =
      TextEditingController(text: widget.user.phone ?? '');
  final _password = TextEditingController();

  late String _role = assignablePlatformRoles.contains(widget.user.role)
      ? widget.user.role
      : assignablePlatformRoles.first;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
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

    final changedPassword = _password.text.isNotEmpty;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(platformUsersProvider.notifier).update(
            widget.user.id,
            UpdatePlatformUserRequest(
              firstName: _firstName.text,
              lastName: _lastName.text,
              email: _email.text,
              role: _role,
              phone: _phone.text,
              password: _password.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changedPassword
                ? 'Saved, and their password was changed.'
                : 'Saved.',
          ),
        ),
      );
    } on ApiException catch (e) {
      // "Email already exists" and "Invalid platform role selected" both come
      // back written for a person to read.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those changes.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Edit ${widget.user.fullName}',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Save changes',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'Required.' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Last name'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'Required.' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
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
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(
            labelText: 'Role',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            for (final role in assignablePlatformRoles)
              DropdownMenuItem(value: role, child: Text(Fmt.label(role))),
          ],
          onChanged: (value) => setState(() => _role = value ?? _role),
        ),
        const SizedBox(height: 20),
        Text(
          'Password',
          style: TextStyle(
            color: bos.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Set a new one',
            helperText: 'Leave empty to keep the one they have',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          validator: (value) {
            // Only checked when something was typed — an empty box is the
            // signal to leave their login alone.
            if (value == null || value.isEmpty) return null;
            return value.length < 8 ? 'At least eight characters.' : null;
          },
        ),
      ],
    );
  }
}
