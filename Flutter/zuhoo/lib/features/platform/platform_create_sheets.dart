import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

/// Adds a member of platform staff.
Future<void> showNewPlatformUserSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewPlatformUserSheet(),
  );
}

/// Defines a new subscription plan.
Future<void> showNewSubscriptionPlanSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewSubscriptionPlanSheet(),
  );
}

// ── Platform staff ────────────────────────────────────────────

class _NewPlatformUserSheet extends ConsumerStatefulWidget {
  const _NewPlatformUserSheet();

  @override
  ConsumerState<_NewPlatformUserSheet> createState() =>
      _NewPlatformUserSheetState();
}

class _NewPlatformUserSheetState
    extends ConsumerState<_NewPlatformUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPassword = false;
  String _role = assignablePlatformRoles.first;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
      await ref.read(platformUsersProvider.notifier).create(
            CreatePlatformUserRequest(
              firstName: _firstName.text,
              lastName: _lastName.text,
              email: _email.text,
              password: _password.text,
              role: _role,
              phone: _phone.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_firstName.text.trim()} added to the team.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add that person.');
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
                'New platform staff',
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
                controller: _firstName,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: _required('A first name is required.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: _required('A last name is required.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: 'They sign in with this.',
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
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  helperText: 'Share it with them; they can change it after.',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    tooltip: _showPassword ? 'Hide' : 'Show',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (value) {
                  final entered = value ?? '';
                  if (entered.isEmpty) return 'Set a password for them.';
                  // The DTO only says @NotBlank, but eight is the floor every
                  // other account in this system is held to.
                  return entered.length < 8
                      ? 'At least eight characters.'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPassword,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) => (value ?? '') == _password.text
                    ? null
                    : 'The two do not match.',
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
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _role = value ?? _role),
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
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Add to team',
                loading: _submitting,
                icon: Icons.person_add_alt_rounded,
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

// ── Subscription plans ────────────────────────────────────────

class _NewSubscriptionPlanSheet extends ConsumerStatefulWidget {
  const _NewSubscriptionPlanSheet();

  @override
  ConsumerState<_NewSubscriptionPlanSheet> createState() =>
      _NewSubscriptionPlanSheetState();
}

class _NewSubscriptionPlanSheetState
    extends ConsumerState<_NewSubscriptionPlanSheet> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();

  String _billingCycle = billingCycles.first;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _price.dispose();
    _description.dispose();
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
      await ref.read(platformRepositoryProvider).createPlan(
            CreateSubscriptionPlanRequest(
              code: _code.text,
              name: _name.text,
              billingCycle: _billingCycle,
              price: double.parse(_price.text.trim()),
              description: _description.text,
            ),
          );
      // The plan picker on every company reads this list.
      ref.invalidate(subscriptionPlansProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} plan created.')),
      );
    } on ApiException catch (e) {
      // A duplicate code lands here and quotes the code back.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create that plan.');
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
                'New subscription plan',
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
                  hintText: 'Growth',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Name the plan.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  helperText: 'Stored upper-case, and has to be unique.',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A code is required.'
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
                  for (final cycle in billingCycles)
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
              TextFormField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'What does it cost?';
                  return parsed < 0 ? 'Cannot be negative.' : null;
                },
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
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Create plan',
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
}
