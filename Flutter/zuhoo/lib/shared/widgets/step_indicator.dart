import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// A row of thin progress segments plus a "Step X of N: Label" caption — the
/// lightweight alternative to a full `Stepper` for a form sheet split into a
/// small, fixed number of screens (an employee's account details vs. their
/// role, an invoice's details vs. its line items). One segment per step,
/// filled up to and including the current one.
class FormStepIndicator extends StatelessWidget {
  const FormStepIndicator({
    super.key,
    required this.labels,
    required this.step,
  });

  final List<String> labels;
  final int step;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: i <= step ? 1 : 0,
                    minHeight: 4,
                    backgroundColor: bos.neutralSoft,
                    valueColor: AlwaysStoppedAnimation(bos.brand),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Step ${step + 1} of ${labels.length}: ${labels[step]}',
          style: TextStyle(
            color: bos.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
