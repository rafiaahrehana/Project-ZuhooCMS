import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';

/// Opens an uploaded file's URL in whatever the device already has for it —
/// the browser for a PDF or an image, a document viewer for anything else.
///
/// `/uploads/**` is served without authentication on the backend (see
/// `SecurityConfig`'s public paths), so there is no token to attach and
/// nothing to download through the API client first: the URL just needs
/// resolving against the server host, the same step [Env.resolveImageUrl]
/// already does for avatars.
Future<void> openAttachmentUrl(BuildContext context, String? url) async {
  final resolved = Env.resolveImageUrl(url);
  if (resolved == null) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final launched = await launchUrl(
      Uri.parse(resolved),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No app on this device can open that file.'),
        ),
      );
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open that file.')),
    );
  }
}
