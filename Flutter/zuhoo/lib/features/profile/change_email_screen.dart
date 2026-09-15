import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newEmail = TextEditingController();
  final _password = TextEditingController();

  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newEmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).changeEmail(
            ChangeEmailRequest(
              email: _newEmail.text.trim(),
              currentPassword: _password.text,
            ),
          );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Email changed. Please sign in again.'),
        ),
      );

      // The JWT carries the email it was issued for, so the next request
      // made with today's token would already fail to resolve a user —
      // signing out here makes that visible now instead of as a confusing
      // failure on the next screen.
      await ref.read(authControllerProvider.notifier).clearSession();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change your email.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final currentEmail = ref.watch(currentUserProvider)?.email;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Change email')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 16),
              ],
              MessageBanner.info(
                'Changing your email signs you out everywhere, including '
                'this device. Use the new address next time you sign in.',
              ),
              const SizedBox(height: 18),
              if (currentEmail != null) ...[
                TextFormField(
                  initialValue: currentEmail,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Current email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _newEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'New email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Enter a new email address.';
                  if (!value.contains('@') ||
                      value.startsWith('@') ||
                      value.endsWith('@')) {
                    return 'Enter a valid email address.';
                  }
                  if (currentEmail != null &&
                      value.toLowerCase() == currentEmail.toLowerCase()) {
                    return 'That is already your email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: !_show,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _show
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: _show ? 'Hide' : 'Show',
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your current password to confirm this change.'
                    : null,
              ),
              const SizedBox(height: 24),
              LoadingButton(
                label: 'Change email',
                loading: _saving,
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
