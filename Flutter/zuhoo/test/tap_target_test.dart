import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/shared/widgets/search_field.dart';

/// Which knob actually changes what a finger can hit.
///
/// These two lines look interchangeable and are not:
///
///   constraints: BoxConstraints(minWidth: 32, minHeight: 32)  // splash only
///   visualDensity: VisualDensity.compact                      // real target
///
/// IconButton defaults to `MaterialTapTargetSize.padded`, which wraps it in
/// enough padding to occupy 48 however small `constraints` are — so shrinking
/// `constraints` shrinks the ink splash and leaves the target alone.
/// `visualDensity` shrinks the padded box itself, and 40 is what comes out.
///
/// Written after "raising" three constraints from 32 and 40, on the assumption
/// they were undersized targets. They were not; the targets were already 48
/// and nothing moved. The buttons that really were under the floor were the
/// ones set to `compact`, which reads as the more innocuous of the two.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(AppAccent.emerald),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('IconButton', () {
    testWidgets('small constraints do not shrink the tap target',
        (tester) async {
      await tester.pumpWidget(_wrap(IconButton(
        onPressed: () {},
        icon: const Icon(Icons.close_rounded, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      )));

      // 48, not 32 — the tap padding is outside the constrained box.
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    });

    testWidgets('visualDensity.compact does, and lands under the floor',
        (tester) async {
      await tester.pumpWidget(_wrap(IconButton(
        onPressed: () {},
        icon: const Icon(Icons.close_rounded, size: 18),
        visualDensity: VisualDensity.compact,
      )));

      // This is the one to avoid: 40 is below the ~44 the app works to.
      expect(tester.getSize(find.byType(IconButton)), const Size(40, 40));
    });

    testWidgets('a corner tap reaches the default button but not the compact one',
        (tester) async {
      var plainTapped = false;
      await tester.pumpWidget(_wrap(IconButton(
        onPressed: () => plainTapped = true,
        icon: const Icon(Icons.close_rounded, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      )));
      await tester.tapAt(
          tester.getCenter(find.byType(IconButton)) + const Offset(23, 23));
      await tester.pump();
      expect(plainTapped, isTrue,
          reason: 'constraints:32 still fills a 48 target');

      var compactTapped = false;
      await tester.pumpWidget(_wrap(IconButton(
        onPressed: () => compactTapped = true,
        icon: const Icon(Icons.close_rounded, size: 18),
        visualDensity: VisualDensity.compact,
      )));
      await tester.tapAt(
          tester.getCenter(find.byType(IconButton)) + const Offset(23, 23));
      await tester.pump();
      expect(compactTapped, isFalse,
          reason: 'compact really is 40 — the corner falls outside it');
    });
  });

  testWidgets('the search field clear button keeps a full target',
      (tester) async {
    await tester.pumpWidget(_wrap(
      SizedBox(
        width: 320,
        child: AppSearchField(onChanged: (_) {}, initial: 'invoice'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsOneWidget);
    expect(tester.getSize(find.byType(IconButton)).height,
        greaterThanOrEqualTo(44));
  });
}
