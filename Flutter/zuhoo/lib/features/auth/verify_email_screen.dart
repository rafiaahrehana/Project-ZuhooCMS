import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

/// Enters the 6-digit code emailed by `POST /api/auth/register`, or resent by
/// hand for someone who registered earlier and never finished.
///
/// [initialEmail] pre-fills the field right after registration, where the
/// address is already known; the field stays editable because this screen is
/// also reachable straight from the login screen's "not verified" message,
/// where it is not.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();

  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .verifyEmail(_email.text.trim(), _code.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified. Sign in to continue.'),
        ),
      );
      context.go(Routes.login);
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

  Future<void> _resend() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email first.');
      return;
    }

    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).resendVerification(email);
      if (!mounted) return;
      setState(() {
        _notice = 'If that account needs verifying, a new code is on its way.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not resend the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Verify your email')),
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
                    Text(
                      'Enter the 6-digit code',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'We emailed a verification code when the account was created.',
                      style: TextStyle(color: bos.muted, fontSize: 13.5),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      MessageBanner.error(
                        _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_notice != null) ...[
                      MessageBanner.info(_notice!),
                      const SizedBox(height: 14),
                    ],
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
                      controller: _code,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(fontSize: 22, letterSpacing: 8),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: '000000',
                        hintStyle: TextStyle(fontSize: 22, letterSpacing: 8),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) == 6
                          ? null
                          : 'Enter the 6-digit code.',
                    ),
                    const SizedBox(height: 20),
                    LoadingButton(
                      label: 'Verify email',
                      loading: _loading,
                      onPressed: _verify,
                    ),
                    Center(
                      child: TextButton(
                        onPressed: _resending || _loading ? null : _resend,
                        child: Text(
                          _resending ? 'Sending…' : 'Resend code',
                        ),
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
