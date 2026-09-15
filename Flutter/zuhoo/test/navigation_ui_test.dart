import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/shared/widgets/search_field.dart';
import 'package:zuhoo/shared/widgets/skeleton.dart';

AppUser _user(List<String> roles) => AppUser(
      id: 1,
      email: 'someone@example.com',
      fullName: 'Ada Lovelace',
      roles: roles,
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(AppAccent.emerald),
      home: Scaffold(body: child),
    );

void main() {
  group('AppUser.roleLabel', () {
    test('turns a backend constant into words', () {
      expect(_user(['COMPANY_OWNER']).roleLabel, 'Company Owner');
      expect(_user(['EMPLOYEE']).roleLabel, 'Employee');
      expect(_user(['PLATFORM_ACCOUNTANT']).roleLabel, 'Platform Accountant');
    });

    test('a user with no roles still gets a label rather than a blank', () {
      // The drawer header prints this unconditionally; an empty string there
      // leaves a gap under the name that reads as a rendering fault.
      expect(_user([]).roleLabel, 'Member');
    });

    test('shows only the first role', () {
      expect(_user(['SUPER_ADMIN', 'SUPPORT_AGENT']).roleLabel, 'Super Admin');
    });
  });

  group('AppSearchField', () {
    testWidgets('debounces, so typing a word is one callback not eight',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_wrap(
        AppSearchField(
          debounce: const Duration(milliseconds: 100),
          onChanged: calls.add,
        ),
      ));

      await tester.enterText(find.byType(TextField), 'e');
      await tester.pump(const Duration(milliseconds: 40));
      await tester.enterText(find.byType(TextField), 'en');
      await tester.pump(const Duration(milliseconds: 40));
      await tester.enterText(find.byType(TextField), 'eng');

      // Nothing yet — the timer keeps being reset while the keys land.
      expect(calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, ['eng']);
    });

    testWidgets('clearing reports immediately rather than after the debounce',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_wrap(
        AppSearchField(initial: 'engineer', onChanged: calls.add),
      ));

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      // No pump past the debounce: getting back to the full list is an
      // explicit act and must not sit behind a delay meant for typing.
      expect(calls, ['']);
    });

    testWidgets('the clear button only exists when there is text to clear',
        (tester) async {
      await tester.pumpWidget(_wrap(AppSearchField(onChanged: (_) {})));
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget);
    });

    testWidgets('trims, so a stray space does not become part of the query',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_wrap(
        AppSearchField(
          debounce: const Duration(milliseconds: 10),
          onChanged: calls.add,
        ),
      ));
      await tester.enterText(find.byType(TextField), '  finance ');
      await tester.pump(const Duration(milliseconds: 30));
      expect(calls, ['finance']);
    });
  });

  group('Skeleton', () {
    testWidgets('holds still when the reader has animations turned off',
        (tester) async {
      // A placeholder is on screen for as long as the network takes, so a
      // looping highlight is exactly what this setting exists to stop.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(AppAccent.emerald),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Skeleton()),
        ),
      ));

      expect(find.byType(ShaderMask), findsNothing);

      // A pump with no scheduled frame would throw if something were still
      // animating, which is the assertion that matters here.
      await tester.pumpAndSettle();
    });

    testWidgets('animates by default', (tester) async {
      await tester.pumpWidget(_wrap(const Skeleton()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('a skeleton list renders the row count it was asked for',
        (tester) async {
      await tester.pumpWidget(_wrap(const SkeletonList(rows: 3)));
      // Three rows, each an avatar circle plus two text bars.
      expect(find.byType(Skeleton), findsNWidgets(9));
    });
  });
}
