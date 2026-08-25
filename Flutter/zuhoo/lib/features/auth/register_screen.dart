import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

final _subdomainPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$');
final _passwordUpper = RegExp(r'[A-Z]');
final _passwordLower = RegExp(r'[a-z]');
final _passwordDigit = RegExp(r'\d');
final _passwordSpecial = RegExp(r'[@$!%*?&#^()_+=\-]');

/// Signs up a brand-new tenant company and its owner — the mobile counterpart
/// of `POST /api/auth/register`. Every field and validation rule mirrors
/// `com.zuhoocms.modules.company.RegisterRequest` exactly, since the backend
/// re-validates all of it regardless of what this form allows through.
///
/// This is only for standing up a company that does not exist yet. Employees
/// and clients are provisioned by their company's owner and never see this
/// screen — they sign in with credentials someone else already created.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _companyName = TextEditingController();
  final _subdomain = TextEditingController();
  final _companyPhone = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _companyName.dispose();
    _subdomain.dispose();
    _companyPhone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await ref.read(authRepositoryProvider).register(
            RegisterRequest(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              email: _email.text.trim(),
              password: _password.text,
              companyName: _companyName.text.trim(),
              subdomain: _subdomain.text.trim(),
              companyPhone: _companyPhone.text,
            ),
          );
      if (!mounted) return;
      context.pushReplacement(Routes.verifyEmail, extra: user.email);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _passwordError(String? v) {
    final value = v ?? '';
    if (value.length < 8) return 'Use at least 8 characters.';
    if (!_passwordUpper.hasMatch(value)) return 'Add an upper-case letter.';
    if (!_passwordLower.hasMatch(value)) return 'Add a lower-case letter.';
    if (!_passwordDigit.hasMatch(value)) return 'Add a digit.';
    if (!_passwordSpecial.hasMatch(value)) {
      return 'Add a special character, e.g. @ ! # ?';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Create your workspace')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
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
                    SectionHeader('Your details', icon: Icons.person_outline_rounded),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstName,
                            textCapitalization: TextCapitalization.words,
                            decoration:
                                const InputDecoration(labelText: 'First name'),
                            validator: (v) => (v?.trim().length ?? 0) < 2
                                ? 'Too short.'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastName,
                            textCapitalization: TextCapitalization.words,
                            decoration:
                                const InputDecoration(labelText: 'Last name'),
                            validator: (v) => (v?.trim().length ?? 0) < 2
                                ? 'Too short.'
                                : null,
                          ),
                        ),
                      ],
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
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Enter your email.';
                        if (!value.contains('@')) return 'Enter a valid email.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          tooltip: _showPassword ? 'Hide' : 'Show',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                        helperText:
                            '8+ characters, upper & lower case, a digit and a symbol',
                        helperMaxLines: 2,
                      ),
                      validator: _passwordError,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: !_showPassword,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_rounded),
                      ),
                      validator: (v) =>
                          v == _password.text ? null : 'Those do not match.',
                    ),
                    const SizedBox(height: 22),
                    SectionHeader('Your company', icon: Icons.business_outlined),
                    TextFormField(
                      controller: _companyName,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Company name'),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Enter a company name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _subdomain,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Subdomain',
                        prefixIcon: Icon(Icons.link_rounded),
                        helperText:
                            'Lower-case letters, numbers and hyphens only, e.g. acme-corp',
                        helperMaxLines: 2,
                      ),
                      onChanged: (v) {
                        final lower = v.toLowerCase();
                        if (lower != v) {
                          _subdomain.value = _subdomain.value.copyWith(
                            text: lower,
                            selection:
                                TextSelection.collapsed(offset: lower.length),
                          );
                        }
                      },
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Choose a subdomain.';
                        if (!_subdomainPattern.hasMatch(value)) {
                          return '3+ characters, lower-case letters, numbers and '
                              'hyphens, not starting or ending with one.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _companyPhone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Company phone (optional)',
                        prefixIcon: Icon(Icons.call_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    LoadingButton(
                      label: 'Create workspace',
                      loading: _loading,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : () => context.pop(),
                        child: const Text('Already have an account? Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
