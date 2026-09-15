import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/form_sheet.dart';
import 'finance_repository.dart';

/// Starts an online checkout to add money to the wallet.
///
/// Same shape as `SubscriptionPlanScreen._upgrade` and
/// `PortalBillingScreen`'s pay-invoice flow: SSLCommerz's hosted checkout is
/// a web page, and the backend's own success/failure callbacks redirect back
/// to the *web* app, not anywhere this app could intercept — so this hands
/// the returned URL to the system browser and asks the person to come back
/// and pull to refresh once they are done.
Future<void> showWalletTopUpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _WalletTopUpSheet(),
  );
}

class _WalletTopUpSheet extends ConsumerStatefulWidget {
  const _WalletTopUpSheet();

  @override
  ConsumerState<_WalletTopUpSheet> createState() => _WalletTopUpSheetState();
}

class _WalletTopUpSheetState extends ConsumerState<_WalletTopUpSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
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
      final amount = double.parse(_amount.text.trim());
      final url =
          await ref.read(financeRepositoryProvider).initiateWalletTopUp(amount);
      final uri = Uri.tryParse(url);
      final launched = uri == null
          ? false
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (mounted) setState(() => _error = 'Could not open the payment page.');
        return;
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Finish paying in the browser, then come back and pull to '
            'refresh.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the payment.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return FormSheetFrame(
      title: 'Top up wallet',
      formKey: _formKey,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      action: 'Continue to payment',
      submitting: _submitting,
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          validator: (value) {
            final parsed = double.tryParse(value?.trim() ?? '');
            if (parsed == null) return 'How much are you adding?';
            return parsed <= 0 ? 'More than nothing.' : null;
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Opens in your browser to complete the payment.',
          style: TextStyle(color: bos.muted, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }
}
