import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/shared/widgets/stat_card.dart';

/// The Home grid has to declare a tile height before it can lay a card out,
/// so the height is computed rather than measured. That makes it the one
/// place a card can be clipped, and the old estimate was clipped: at a 1.5
/// text scale "Attendance this month" lost its second line behind the
/// overflow stripe.
///
/// The overflow is only visible on a device — it does not reach logcat — so
/// it is asserted here instead, at the scales a reader can actually pick.
Widget _grid(double scale, List<StatCard> cards) => MaterialApp(
      theme: AppTheme.light(AppAccent.emerald),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SizedBox(
            width: 380,
            // The same rows-of-two the Home screen builds.
            child: Column(
              children: [
                for (var i = 0; i < cards.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[i]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: i + 1 < cards.length
                              ? cards[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

/// The real Home cards, including the two long labels that wrap to two lines.
List<StatCard> _cards() => const [
      StatCard(
        label: 'Attendance this month',
        value: '85',
        suffix: '%',
        icon: Icons.event_available_rounded,
      ),
      StatCard(
        label: 'Leave days available',
        value: '44',
        icon: Icons.beach_access_rounded,
      ),
      StatCard(
        label: 'Open requests',
        value: '0',
        icon: Icons.assignment_outlined,
      ),
      StatCard(
        label: 'Latest review score',
        value: null,
        icon: Icons.star_outline_rounded,
      ),
    ];

void main() {
  group('the Home stat grid fits its cards', () {
    // 2.0 is what Android offers at the top of its font-size slider; 1.5 is
    // the setting the clipping was found at.
    for (final scale in const [1.0, 1.15, 1.3, 1.5, 1.8, 2.0]) {
      testWidgets('at a text scale of $scale', (tester) async {
        await tester.pumpWidget(_grid(scale, _cards()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'a card overflowed its tile at scale $scale');
      });
    }
  });

  testWidgets('the two cards in a row share a height', (tester) async {
    // "Attendance this month" wraps to two lines and "Open requests" does
    // not; without IntrinsicHeight the pair would be visibly uneven.
    await tester.pumpWidget(_grid(1.0, _cards()));
    await tester.pumpAndSettle();
    final sizes = tester
        .widgetList<StatCard>(find.byType(StatCard))
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toList();
    expect(sizes[0], sizes[1]);
    expect(sizes[2], sizes[3]);
  });
}
