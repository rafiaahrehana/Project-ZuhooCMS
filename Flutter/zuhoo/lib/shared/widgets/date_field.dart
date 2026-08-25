import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import '../util/formatters.dart';

/// A tappable date, shaped like the text fields either side of it.
///
/// Flutter has no date input that sits in a form the way `TextFormField` does,
/// so this is an `InputDecorator` doing the same job: same label, same border,
/// same height, so a form with a date in the middle of it does not visibly
/// break stride.
///
/// Clearing is offered only when there is something to clear — a permanent
/// clear button on an empty field reads as an action that does nothing.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon = Icons.event_outlined,
    this.enabled = true,
    this.firstDate,
    this.lastDate,
    this.emptyText = 'Not set',
    this.clearable = true,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final IconData icon;
  final bool enabled;

  /// False for a date the endpoint refuses to accept empty. Without this the
  /// field would offer a clear button that the caller has to ignore, which is
  /// worse than not offering one.
  final bool clearable;

  /// Defaults span a working range either side of today. Callers that mean
  /// something narrower — a purchase cannot be in the future, a deadline
  /// usually is not in the past — pass their own.
  final DateTime? firstDate;
  final DateTime? lastDate;

  final String emptyText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 5),
      lastDate: lastDate ?? DateTime(now.year + 5),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: value == null || !clearable
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: bos.muted),
                  tooltip: 'Clear',
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
        ),
        child: Text(
          value == null ? emptyText : Fmt.date(Fmt.isoDate(value!)),
          style: TextStyle(
            color: value == null ? bos.muted : bos.text,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
