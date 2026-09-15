import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/primitives.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String? _error;
  bool _unverified = false;
  bool _startingDemo = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _unverified = false;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text, _password.text);
      // No navigation here: the router's redirect watches the auth state and
      // moves us as soon as it flips. Pushing as well would race it.
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          // The backend's own wording for this case ("Your email address has
          // not been verified...") — matched loosely so a rewording of the
          // rest of the sentence does not silently drop this shortcut.
          _unverified = e.isForbidden &&
              e.message.toLowerCase().contains('not been verified');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens the read-only demo tenant. No credentials are exchanged — the
  /// backend mints a short session for the seeded company.
  Future<void> _startDemo() async {
    if (_loading || _startingDemo) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _startingDemo = true;
      _error = null;
      _unverified = false;
    });

    try {
      await ref.read(authControllerProvider.notifier).startDemo();
      // As with _submit: the router's redirect moves us when the auth state
      // flips, and navigating here as well would race it.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The demo could not be started. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _startingDemo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(bos: bos),
                  const SizedBox(height: 28),
                  AppCard(
                    padding: const EdgeInsets.all(22),
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
                            if (_unverified) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => context.push(
                                    Routes.verifyEmail,
                                    extra: _email.text.trim(),
                                  ),
                                  child: const Text('Verify my email'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'you@company.com',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Enter your email.';
                              if (!value.contains('@') || !value.contains('.')) {
                                return 'Enter a valid email.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _showPassword ? 'Hide' : 'Show',
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password.'
                                : null,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => context.push(Routes.forgotPassword),
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          LoadingButton(
                            label: _loading ? 'Signing in...' : 'Sign in',
                            loading: _loading,
                            icon: Icons.login_rounded,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Divider(color: bos.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(color: bos.muted, fontSize: 12.5),
                        ),
                      ),
                      Expanded(child: Divider(color: bos.border)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading || _startingDemo ? null : _startDemo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: bos.brandInk,
                        side: BorderSide(color: bos.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _startingDemo
                          ? SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: bos.brandInk,
                              ),
                            )
                          : const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(
                        _startingDemo ? 'Opening the demo...' : 'Explore the demo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Said before they go in, not after: somebody who spends ten
                  // minutes filling in a form only to be refused at Save has
                  // been misled, and the refusal comes from the backend where
                  // no wording of ours can soften it.
                  Text(
                    'A live, read-only tour. Nothing you change is saved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _loading || _startingDemo
                        ? null
                        : () => context.push(Routes.register),
                    child: const Text("Don't have a workspace? Create one"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bos});

  final BosPalette bos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandMark(size: 64),
        const SizedBox(height: 16),
        Text(
          'Zuhoo',
          style: TextStyle(
            color: bos.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to your workspace',
          style: TextStyle(color: bos.muted, fontSize: 14),
        ),
      ],
    );
  }
}
