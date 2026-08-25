import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import 'primitives.dart';

/// Shared chrome for a bottom-sheet form.
///
/// Every editing sheet in the app is the same three things — a title, an
/// optional error banner and a column of fields over a submit button — so the
/// frame is written once here rather than per feature. It handles the two
/// details that are easy to get wrong in a sheet: lifting the content clear of
/// the keyboard, and scrolling when the fields outgrow the screen.
class FormSheetFrame extends StatelessWidget {
  const FormSheetFrame({
    super.key,
    required this.title,
    required this.formKey,
    required this.error,
    required this.onDismissError,
    required this.action,
    required this.submitting,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;

  /// Shown above the fields, dismissable. Null when nothing has failed.
  final String? error;
  final VoidCallback onDismissError;

  /// The submit button's label — "Add department", "Save changes".
  final String action;
  final bool submitting;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (error != null) ...[
                MessageBanner.error(error!, onDismiss: onDismissError),
                const SizedBox(height: 14),
              ],
              ...children,
              const SizedBox(height: 18),
              LoadingButton(
                label: action,
                loading: submitting,
                icon: Icons.check_rounded,
                onPressed: onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
