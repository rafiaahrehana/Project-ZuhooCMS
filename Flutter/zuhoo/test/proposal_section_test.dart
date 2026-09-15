import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/features/requests/proposal_models.dart';
import 'package:zuhoo/features/requests/proposal_section.dart';
import 'package:zuhoo/features/requests/request_controllers.dart';

/// Who is offered which button.
///
/// The proposal is the one card in this app serving two people with opposite
/// permissions: `ProposalServiceImpl` lets staff write and send, and lets the
/// client accept or ask for changes, and refuses each the other's half. The
/// card decides that locally, so this is where the decision is checked —
/// offering the wrong button does not fail until somebody taps it and gets a
/// 403 they can do nothing about.
const _requestId = 22;

Widget _wrap({required bool isStaff, Proposal? proposal}) => ProviderScope(
      overrides: [
        requestProposalProvider(_requestId).overrideWith((ref) async => proposal),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppAccent.emerald),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProposalSection(id: _requestId, isStaff: isStaff),
          ),
        ),
      ),
    );

Proposal _at(String status, {String? feedback}) => Proposal.fromJson({
      'id': 7,
      'serviceRequestId': _requestId,
      'title': 'Distributor order tracking',
      'status': status,
      'techStack': 'Flutter, Spring Boot',
      'timeline': '10-12 weeks',
      'estimatedBudget': 'BDT 4-6 lakh',
      'clientFeedback': feedback,
    });

void main() {
  group('staff', () {
    testWidgets('are invited to draft one when there is none', (tester) async {
      await tester.pumpWidget(_wrap(isStaff: true, proposal: null));
      await tester.pumpAndSettle();
      expect(find.text('Draft a proposal'), findsOneWidget);
    });

    testWidgets('can edit and send a draft', (tester) async {
      await tester.pumpWidget(
          _wrap(isStaff: true, proposal: _at(ProposalStatus.draft)));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('get no buttons once it is sent, and are told why',
        (tester) async {
      // save() and send() both refuse a SENT proposal, so offering either
      // would be a button that cannot work.
      await tester.pumpWidget(
          _wrap(isStaff: true, proposal: _at(ProposalStatus.sent)));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Send'), findsNothing);
      expect(find.textContaining('waiting on the client'), findsOneWidget);
    });

    testWidgets('can revise after the client asks for changes', (tester) async {
      await tester.pumpWidget(_wrap(
        isStaff: true,
        proposal: _at(ProposalStatus.changesRequested,
            feedback: 'Split the delivery flow out of phase 1.'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      // The wording changes, because re-sending is not the same act as
      // sending it for the first time.
      expect(find.text('Send revision'), findsOneWidget);
      expect(
        find.textContaining('Split the delivery flow out of phase 1.'),
        findsOneWidget,
        reason: "the client's reason is the whole point of the round trip",
      );
    });

    testWidgets('get nothing further once it is accepted', (tester) async {
      await tester.pumpWidget(
          _wrap(isStaff: true, proposal: _at(ProposalStatus.accepted)));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Send'), findsNothing);
      expect(find.text('Accept'), findsNothing);
    });
  });

  group('the client', () {
    testWidgets('sees nothing at all when no proposal has been drafted',
        (tester) async {
      // Not an empty-state card: explaining the absence of something they
      // were never promised is worse than staying quiet.
      await tester.pumpWidget(_wrap(isStaff: false, proposal: null));
      await tester.pumpAndSettle();
      expect(find.text('Proposal'), findsNothing);
      expect(find.text('Draft a proposal'), findsNothing);
    });

    testWidgets('can accept or ask for changes once it is sent',
        (tester) async {
      await tester.pumpWidget(
          _wrap(isStaff: false, proposal: _at(ProposalStatus.sent)));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Request changes'), findsOneWidget);
      // The staff half is never theirs.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Send'), findsNothing);
    });

    testWidgets('cannot respond to a draft they should not be seeing yet',
        (tester) async {
      // accept() and request-changes() both require SENT.
      await tester.pumpWidget(
          _wrap(isStaff: false, proposal: _at(ProposalStatus.draft)));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Request changes'), findsNothing);
    });

    testWidgets('cannot respond twice', (tester) async {
      await tester.pumpWidget(
          _wrap(isStaff: false, proposal: _at(ProposalStatus.accepted)));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Request changes'), findsNothing);
    });
  });

  testWidgets('the card shows what was actually proposed', (tester) async {
    await tester.pumpWidget(
        _wrap(isStaff: true, proposal: _at(ProposalStatus.draft)));
    await tester.pumpAndSettle();
    expect(find.text('Distributor order tracking'), findsOneWidget);
    expect(find.text('Flutter, Spring Boot'), findsOneWidget);
    expect(find.text('10-12 weeks'), findsOneWidget);
    expect(find.text('BDT 4-6 lakh'), findsOneWidget);
  });
}
