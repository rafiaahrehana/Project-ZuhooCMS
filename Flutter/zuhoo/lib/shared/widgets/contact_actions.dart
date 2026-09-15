import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'primitives.dart';

/// Call and email — the two actions a phone number and an address exist
/// for. Extracted from the employee directory's own detail screen so every
/// entity with a phone/email (a lead, a client, an employee, a candidate)
/// gets the same one-tap buttons instead of a plain text row nobody can act
/// on without leaving the app to dial by hand.
///
/// Renders nothing when neither is present, unless [emptyMessage] is given —
/// some screens want to say so explicitly, others (where a missing number is
/// the normal case) would rather the row just not be there.
class ContactActions extends StatelessWidget {
  const ContactActions({super.key, this.phone, this.email, this.emptyMessage});

  final String? phone;
  final String? email;
  final String? emptyMessage;

  Future<void> _launch(BuildContext context, Uri uri, String failure) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        messenger.showSnackBar(SnackBar(content: Text(failure)));
      }
    } catch (_) {
      // A device with no dialer or no mail account configured — an emulator,
      // usually. Worth saying so rather than failing silently.
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    final hasEmail = email != null && email!.trim().isNotEmpty;

    if (!hasPhone && !hasEmail) {
      final message = emptyMessage;
      return message == null
          ? const SizedBox.shrink()
          : AppCard(child: MessageBanner.info(message));
    }

    return Row(
      children: [
        if (hasPhone)
          Expanded(
            child: ContactActionButton(
              icon: Icons.call_rounded,
              label: 'Call',
              onTap: () => _launch(
                context,
                Uri(scheme: 'tel', path: phone),
                'No app on this device can place a call.',
              ),
            ),
          ),
        if (hasPhone && hasEmail) const SizedBox(width: 10),
        if (hasEmail)
          Expanded(
            child: ContactActionButton(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              onTap: () => _launch(
                context,
                Uri(scheme: 'mailto', path: email),
                'No mail app is set up on this device.',
              ),
            ),
          ),
      ],
    );
  }
}

class ContactActionButton extends StatelessWidget {
  const ContactActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }
}
