import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/kb/kb_models.dart';
import 'package:zuhoo/features/requests/request_workflow_models.dart';

void main() {
  group('StageProgress', () {
    test('currentStage counts completed stages rather than indexing them', () {
      final progress = StageProgress.fromJson(const {
        'serviceRequestId': 7,
        'currentStage': 2,
        'totalStages': 4,
        'stages': [
          {'stageId': 1, 'name': 'Intake', 'stageOrder': 1, 'completed': true},
          {'stageId': 2, 'name': 'Review', 'stageOrder': 2, 'completed': true},
          {
            'stageId': 3,
            'name': 'Filing',
            'stageOrder': 3,
            'current': true,
            'requiresApproval': true,
          },
          {'stageId': 4, 'name': 'Handover', 'stageOrder': 4},
        ],
      });

      expect(progress.fraction, 0.5);
      expect(progress.finished, isFalse);
      // Two done means stages[2] is in flight, not stages[1].
      expect(progress.inFlight?.name, 'Filing');
      expect(progress.inFlight?.requiresApproval, isTrue);
    });

    test('falls back to the index when no stage is flagged current', () {
      final progress = StageProgress.fromJson(const {
        'currentStage': 1,
        'totalStages': 2,
        'stages': [
          {'stageId': 1, 'name': 'One', 'completed': true},
          {'stageId': 2, 'name': 'Two'},
        ],
      });

      expect(progress.inFlight?.name, 'Two');
    });

    test('a finished workflow has nothing in flight', () {
      final progress = StageProgress.fromJson(const {
        'currentStage': 2,
        'totalStages': 2,
        'stages': [
          {'stageId': 1, 'name': 'One', 'completed': true},
          {'stageId': 2, 'name': 'Two', 'completed': true},
        ],
      });

      expect(progress.finished, isTrue);
      expect(progress.inFlight, isNull);
    });

    test('no workflow at all does not divide by zero', () {
      final progress = StageProgress.fromJson(const {});
      expect(progress.fraction, 0);
      expect(progress.finished, isFalse);
      expect(progress.stages, isEmpty);
    });
  });

  group('TaskRequest', () {
    test('omits what was not set, because updateTask null-checks every field',
        () {
      const request = TaskRequest(status: TaskStatus.completed);
      expect(request.toJson(), {'status': 'COMPLETED'});
    });

    test('carries the stage only when creating', () {
      const request = TaskRequest(title: 'File it', workflowStageId: 3);
      expect(request.toJson(), {'title': 'File it', 'workflowStageId': 3});
    });
  });

  group('QuotationRequest', () {
    test('always sends every field, since the backend assigns them blind', () {
      const request = QuotationRequest(amount: 1200, currency: 'SAR');
      final json = request.toJson();

      // Not `contains` — the point is that the null keys are present, so a
      // re-quote clears the old note rather than leaving a stale one behind.
      expect(json.keys.toSet(), {'amount', 'currency', 'notes', 'validUntil'});
      expect(json['notes'], isNull);
      expect(json['validUntil'], isNull);
    });
  });

  group('KbArticleRequest', () {
    test('a round trip through from() preserves what the form never shows', () {
      final article = KbArticle.fromJson(const {
        'id': 4,
        'title': 'Refund policy',
        'content': 'Refunds within 14 days.',
        'summary': 'How refunds work',
        'keywords': 'refund, returns',
        'status': 'PUBLISHED',
        'clientVisible': true,
        'categoryId': 9,
        'relatedServiceId': 12,
      });

      final json = KbArticleRequest.from(article)
          .copyWith(title: 'Refunds')
          .toJson();

      expect(json['title'], 'Refunds');
      // The two the edit form has no field for. Dropping either would detach
      // the article from its category or its service.
      expect(json['categoryId'], 9);
      expect(json['relatedServiceId'], 12);
      // A Java primitive on the request DTO: an absent key would arrive as
      // false and quietly hide the article from clients.
      expect(json['clientVisible'], isTrue);
    });

    test('sends every key so an omission cannot be read as "leave it"', () {
      const request = KbArticleRequest(
        title: 'Draft',
        content: 'Body',
        clientVisible: false,
      );

      expect(request.toJson().keys.toSet(), {
        'title',
        'content',
        'clientVisible',
        'summary',
        'keywords',
        'categoryId',
        'relatedServiceId',
      });
    });
  });
}
