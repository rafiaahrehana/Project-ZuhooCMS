import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import 'notification_repository.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
          'Every switch below goes back to what a new account starts with.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationPreferencesProvider.notifier).resetToDefaults();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reset your preferences.')),
      );
    }
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences updated,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationPreferencesProvider.notifier).save(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save that change.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: async.value == null ? null : () => _reset(context, ref),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your notification preferences.',
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (prefs) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const SectionHeader('Email', icon: Icons.mail_outline_rounded),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _Switch(
                    label: 'Service requests',
                    value: prefs.emailOnServiceRequest,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(emailOnServiceRequest: v),
                    ),
                  ),
                  _Switch(
                    label: 'Status changes',
                    value: prefs.emailOnStatusChange,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(emailOnStatusChange: v),
                    ),
                  ),
                  _Switch(
                    label: 'Invoices',
                    value: prefs.emailOnInvoice,
                    onChanged: (v) =>
                        _toggle(context, ref, prefs.copyWith(emailOnInvoice: v)),
                  ),
                  _Switch(
                    label: 'Payments',
                    value: prefs.emailOnPayment,
                    onChanged: (v) =>
                        _toggle(context, ref, prefs.copyWith(emailOnPayment: v)),
                  ),
                  _Switch(
                    label: 'Task assigned to me',
                    value: prefs.emailOnTaskAssigned,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(emailOnTaskAssigned: v),
                    ),
                  ),
                  _Switch(
                    label: 'Leave updates',
                    value: prefs.emailOnLeaveUpdate,
                    isLast: true,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(emailOnLeaveUpdate: v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const SectionHeader('In-app', icon: Icons.notifications_outlined),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _Switch(
                    label: 'Service requests',
                    value: prefs.inAppOnServiceRequest,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(inAppOnServiceRequest: v),
                    ),
                  ),
                  _Switch(
                    label: 'Status changes',
                    value: prefs.inAppOnStatusChange,
                    isLast: true,
                    onChanged: (v) => _toggle(
                      context,
                      ref,
                      prefs.copyWith(inAppOnStatusChange: v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const SectionHeader('Other', icon: Icons.campaign_outlined),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _Switch(
                label: 'Product news and offers',
                value: prefs.emailMarketing,
                isLast: true,
                onChanged: (v) =>
                    _toggle(context, ref, prefs.copyWith(emailMarketing: v)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      children: [
        SwitchListTile(
          value: value,
          onChanged: onChanged,
          title: Text(label, style: const TextStyle(fontSize: 14.5)),
          activeThumbColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        if (!isLast) Divider(height: 1, indent: 16, color: bos.borderLight),
      ],
    );
  }
}
