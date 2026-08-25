import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// The two dialogs that appear before an action that cannot be taken back.
///
/// Both return null when dismissed, and null is never a "yes" — an empty
/// string from [askForText] means "confirmed, with nothing typed", which is a
/// different answer from "cancelled" and must not be collapsed into it.

/// Asks whether to go ahead.
///
/// [action] is the affirmative button's label and should name what happens —
/// "Remove", "Cancel the run" — rather than saying "OK", so the button still
/// reads correctly when somebody skips the sentence above it.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final bos = Theme.of(dialogContext).bos;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: bos.danger)
                : null,
            child: Text(action),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Asks for one line of text, then whether to go ahead.
///
/// Set [required] when the endpoint refuses an empty value — several reject
/// and approve endpoints declare their reason as a non-optional
/// `@RequestParam`, and a 400 after the fact is a worse way to learn that than
/// a disabled button.
///
/// Returns null when dismissed. An empty string means confirmed with nothing
/// typed, which is valid wherever [required] is false.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  required String action,
  bool required = false,
  bool destructive = false,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final bos = Theme.of(dialogContext).bos;
      return StatefulBuilder(
        builder: (context, setState) {
          final filled = controller.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: TextStyle(color: bos.muted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Never mind'),
              ),
              TextButton(
                onPressed: (required && !filled)
                    ? null
                    : () => Navigator.pop(dialogContext, controller.text),
                style: destructive
                    ? TextButton.styleFrom(foregroundColor: bos.danger)
                    : null,
                child: Text(action),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return result;
}

/// Picks one value from a short list, as a sheet rather than a dropdown.
///
/// For status changes and the like, where the options are few, each needs a
/// readable label, and the current one should be visibly current.
Future<String?> pickOne(
  BuildContext context, {
  required List<({String value, String label})> options,
  String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final option in options)
            ListTile(
              title: Text(option.label),
              trailing: option.value == current
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(sheetContext, option.value),
            ),
        ],
      ),
    ),
  );
}
