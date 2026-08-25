import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import 'portal_models.dart';
import 'portal_repository.dart';

/// What a portal client may change about their own account.
///
/// Narrower than the staff-side client form on purpose: `PATCH /clients/me`
/// accepts company details and addresses only. Name, email and account status
/// belong to the company that owns the relationship — a client able to edit
/// their own status could reopen an account the company had closed.
Future<void> showEditPortalProfileSheet(
  BuildContext context,
  ClientProfile profile,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditPortalProfileSheet(profile: profile),
  );
}

class _EditPortalProfileSheet extends ConsumerStatefulWidget {
  const _EditPortalProfileSheet({required this.profile});

  final ClientProfile profile;

  @override
  ConsumerState<_EditPortalProfileSheet> createState() =>
      _EditPortalProfileSheetState();
}

class _EditPortalProfileSheetState
    extends ConsumerState<_EditPortalProfileSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _company;
  late final TextEditingController _industry;
  late final TextEditingController _website;
  late final TextEditingController _billingAddress;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _company = TextEditingController(text: profile.clientCompanyName ?? '');
    _industry = TextEditingController(text: profile.industry ?? '');
    _website = TextEditingController(text: profile.website ?? '');
    _billingAddress = TextEditingController(text: profile.billingAddress ?? '');
  }

  @override
  void dispose() {
    _company.dispose();
    _industry.dispose();
    _website.dispose();
    _billingAddress.dispose();
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
      await ref.read(portalRepositoryProvider).updateProfile(
            UpdateMyProfileRequest(
              clientCompanyName: _company.text,
              industry: _industry.text,
              website: _website.text,
              billingAddress: _billingAddress.text,
            ),
          );
      // Refetched rather than patched locally: the response is the whole
      // profile and several screens read it, so one source of truth wins.
      ref.invalidate(clientProfileProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Details updated.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those details.');
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
                'Edit your details',
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
                controller: _company,
                autofocus: true,
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
                controller: _billingAddress,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Billing address',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: bos.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To change your name or email, ask your account manager.',
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
                label: 'Save details',
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
