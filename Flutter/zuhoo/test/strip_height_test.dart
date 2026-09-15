import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/core/theme/bos_tokens.dart';
import 'package:zuhoo/shared/widgets/config_list.dart';
import 'package:zuhoo/shared/widgets/primitives.dart';

/// Fixed-height strips holding text are the app's recurring overflow bug: the
/// height gets budgeted against what the text measured on one device, and
/// anything that makes the text taller — a different font metric, a reader who
/// has turned their text size up — pushes it over.
///
/// The payroll trend chart shipped one pixel over, which is what these cover.
Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(AppAccent.emerald),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('scaledStripHeight', () {
    testWidgets('returns the base when the reader has not changed anything',
        (tester) async {
      late double height;
      await tester.pumpWidget(_wrap(Builder(
        builder: (context) {
          height = scaledStripHeight(context, 52);
          return const SizedBox();
        },
      )));
      expect(height, 52);
    });

    testWidgets('grows with the text size', (tester) async {
      late double height;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            height = scaledStripHeight(context, 52);
            return const SizedBox();
          },
        ),
        textScale: 1.5,
      ));
      expect(height, greaterThan(52));
    });

    testWidgets('stops growing, so a strip cannot eat the screen',
        (tester) async {
      late double huge;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            huge = scaledStripHeight(context, 52);
            return const SizedBox();
          },
        ),
        textScale: 4,
      ));
      // The curve clamps at +1.5 scale, so 52 + 1.5 * 26.
      expect(huge, 52 + 1.5 * 26);
    });
  });

  group('FilterBar', () {
    Widget bar() => FilterBar(
          options: const [
            (value: null, label: 'Everything'),
            (value: 'OPEN', label: 'Still open'),
            (value: 'DONE', label: 'Finished'),
          ],
          selected: null,
          onSelected: (_) {},
        );

    testWidgets('does not overflow at the default text size', (tester) async {
      await tester.pumpWidget(_wrap(bar()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow when the text size is turned up',
        (tester) async {
      // The case a fixed height fails: same chips, taller labels.
      await tester.pumpWidget(_wrap(bar(), textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks the selection in the brand colour, not the fallback',
        (tester) async {
      // The selected chip had no colour of its own, so it fell through to
      // secondaryContainer — derived from the info blue — with the label
      // still painted for the unselected background. Both halves are checked
      // here because setting only the fill leaves unreadable dark-on-blue.
      for (final accent in AppAccent.values) {
        final theme = AppTheme.light(accent);
        final bos = theme.extension<BosPalette>()!;

        expect(theme.chipTheme.selectedColor, bos.brand);
        expect(theme.chipTheme.secondarySelectedColor, bos.brand,
            reason: 'ChoiceChip reads the secondary pair when selected');
        expect(theme.chipTheme.secondaryLabelStyle?.color, Colors.white);
        expect(theme.chipTheme.checkmarkColor, Colors.white);

        // The whole point: not the colour it used to fall back to.
        expect(theme.chipTheme.selectedColor, isNot(theme.colorScheme.secondary));
      }
    });
  });
}
