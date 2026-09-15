import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/shared/widgets/config_list.dart';

Widget _list(AsyncValue<List<String>> async, {Widget? header}) => MaterialApp(
      theme: AppTheme.light(AppAccent.emerald),
      home: Scaffold(
        body: ConfigList<String>(
          async: async,
          header: header,
          onRefresh: () async {},
          emptyTitle: 'Nothing recorded',
          emptyMessage: 'No attendance has been recorded for this day yet.',
          errorMessage: 'Could not load the list.',
          itemBuilder: (_, row) => Text(row),
        ),
      ),
    );

void main() {
  group('ConfigList header', () {
    testWidgets('survives an empty list', (tester) async {
      // The regression this exists for: team attendance puts its
      // previous/next-day buttons in the header, and the header used to be
      // dropped along with the rows. Landing on a day nobody clocked in on —
      // a weekend, a holiday, any day before the company started using this —
      // left the screen with no way to move to another one.
      await tester.pumpWidget(_list(
        const AsyncValue.data(<String>[]),
        header: const Text('Previous day'),
      ));

      expect(find.text('Previous day'), findsOneWidget);
      expect(find.text('Nothing recorded'), findsOneWidget);
    });

    testWidgets('is drawn once when the list has rows', (tester) async {
      await tester.pumpWidget(_list(
        const AsyncValue.data(['a', 'b']),
        header: const Text('Previous day'),
      ));

      expect(find.text('Previous day'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('an empty list without a header still says so', (tester) async {
      await tester.pumpWidget(_list(const AsyncValue.data(<String>[])));
      expect(find.text('Nothing recorded'), findsOneWidget);
    });

    testWidgets('a failure shows the error, not the empty state',
        (tester) async {
      // Distinct states: "there is nothing" and "we could not find out" are
      // different answers and must not be shown as the same one.
      await tester.pumpWidget(_list(
        AsyncValue.error(Exception('boom'), StackTrace.empty),
        header: const Text('Previous day'),
      ));

      expect(find.text('Could not load the list.'), findsOneWidget);
      expect(find.text('Nothing recorded'), findsNothing);
    });
  });
}
