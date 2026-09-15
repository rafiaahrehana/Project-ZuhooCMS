import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/requests/proposal_models.dart';

/// The proposal's rules are the backend's rules.
///
/// `ProposalServiceImpl` decides what may happen in each state, and the card
/// mirrors those decisions so it never offers a button that answers 400. That
/// duplication is the risk this file covers: if the two ever disagree, it is
/// these expectations that should fail rather than a user's tap.
void main() {
  Proposal at(String status, {String? feedback}) => Proposal.fromJson({
        'id': 7,
        'serviceRequestId': 22,
        'title': 'Inventory system',
        'status': status,
        'clientFeedback': feedback,
      });

  group('what may happen in each state', () {
    test('a draft can be edited and sent', () {
      // ProposalServiceImpl.save allows DRAFT; send allows DRAFT.
      final p = at(ProposalStatus.draft);
      expect(p.canEdit, isTrue);
      expect(p.canSend, isTrue);
      expect(p.awaitsClient, isFalse);
      expect(p.isSettled, isFalse);
    });

    test('a sent proposal is frozen until the client answers', () {
      // save() throws "Cannot edit a proposal that has already been sent".
      final p = at(ProposalStatus.sent);
      expect(p.canEdit, isFalse);
      expect(p.canSend, isFalse);
      expect(p.awaitsClient, isTrue,
          reason: 'accept and request-changes are only allowed from SENT');
    });

    test('changes requested reopens it for editing and re-sending', () {
      final p = at(ProposalStatus.changesRequested);
      expect(p.canEdit, isTrue);
      expect(p.canSend, isTrue);
      // The client has already had their turn; they cannot respond again
      // until it is sent back to them.
      expect(p.awaitsClient, isFalse);
    });

    test('an accepted proposal is finished', () {
      final p = at(ProposalStatus.accepted);
      expect(p.canEdit, isFalse, reason: 'save() refuses an accepted proposal');
      expect(p.canSend, isFalse);
      expect(p.awaitsClient, isFalse);
      expect(p.isSettled, isTrue);
    });

    test('an unfamiliar status offers nothing rather than guessing', () {
      // A newer backend adding a state should freeze the card, not let the
      // app act on a lifecycle it does not understand.
      final p = at('SOMETHING_NEW');
      expect(p.canEdit, isFalse);
      expect(p.canSend, isFalse);
      expect(p.awaitsClient, isFalse);
      expect(p.isSettled, isFalse);
    });
  });

  group('Proposal.fromJson', () {
    test('reads the response the backend documents', () {
      final p = Proposal.fromJson({
        'id': 3,
        'serviceRequestId': 22,
        'title': 'Warehouse rollout',
        'techStack': 'Flutter, Spring Boot',
        'timeline': '10-12 weeks',
        'summary': 'Two milestones.',
        'estimatedBudget': 'BDT 4-6 lakh',
        'status': 'SENT',
        'clientFeedback': null,
        'createdByName': 'Tanvir Ahmed',
        'sentAt': '2026-08-30T10:00:00',
        'attachments': [
          {'id': 1, 'fileName': 'scope.pdf', 'fileUrl': '/f/1', 'label': 'Scope'},
        ],
      });

      expect(p.title, 'Warehouse rollout');
      expect(p.estimatedBudget, 'BDT 4-6 lakh');
      expect(p.createdByName, 'Tanvir Ahmed');
      expect(p.attachments.single.displayName, 'Scope');
    });

    test('an attachment with no label falls back to its file name', () {
      // A column of "attachment, attachment, attachment" tells nobody which
      // one they want.
      const a = ProposalAttachment(id: 1, fileName: 'mockups.pdf', fileUrl: '/f/1');
      expect(a.displayName, 'mockups.pdf');
      const blank = ProposalAttachment(
          id: 2, fileName: 'spec.pdf', fileUrl: '/f/2', label: '   ');
      expect(blank.displayName, 'spec.pdf');
    });

    test('a nearly-empty body still yields a usable object', () {
      // The list endpoint and the detail endpoint share this shape, and a
      // freshly created draft has almost nothing filled in.
      final p = Proposal.fromJson({'id': 1});
      expect(p.title, 'Proposal');
      expect(p.status, ProposalStatus.draft);
      expect(p.attachments, isEmpty);
      expect(p.canEdit, isTrue);
    });
  });

  group('ProposalRequest', () {
    test('sends every field, so clearing one actually clears it', () {
      // PUT is a full replace rather than a sparse patch: omitting a field
      // the user emptied would silently keep the old value.
      final json = const ProposalRequest(title: 'Only a title').toJson();
      expect(json['title'], 'Only a title');
      for (final key in ['techStack', 'timeline', 'summary', 'estimatedBudget']) {
        expect(json.containsKey(key), isTrue, reason: '$key must be sent');
        expect(json[key], isNull);
      }
    });

    test('blank entries are sent as null, not as empty strings', () {
      final json = const ProposalRequest(
        title: '  Warehouse rollout  ',
        techStack: '   ',
        timeline: '',
        summary: 'Two milestones.',
      ).toJson();
      expect(json['title'], 'Warehouse rollout');
      expect(json['techStack'], isNull);
      expect(json['timeline'], isNull);
      expect(json['summary'], 'Two milestones.');
    });

    test('seeds an edit from the proposal so nothing on screen is lost', () {
      final existing = Proposal.fromJson({
        'id': 3,
        'title': 'Warehouse rollout',
        'techStack': 'Flutter',
        'timeline': '10 weeks',
        'summary': 'Two milestones.',
        'estimatedBudget': 'BDT 5 lakh',
        'status': 'DRAFT',
      });
      final json = ProposalRequest.from(existing).toJson();
      expect(json['title'], 'Warehouse rollout');
      expect(json['techStack'], 'Flutter');
      expect(json['timeline'], '10 weeks');
      expect(json['summary'], 'Two milestones.');
      expect(json['estimatedBudget'], 'BDT 5 lakh');
    });
  });
}
