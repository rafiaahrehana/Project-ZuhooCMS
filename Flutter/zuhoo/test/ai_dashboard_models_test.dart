import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/ai/ai_admin_models.dart';
import 'package:zuhoo/features/dashboard/dashboard_models.dart';
import 'package:zuhoo/features/profile/employee_models.dart';

void main() {
  group('AiProviderConfigRequest', () {
    test('a blank key is left out, so the stored one survives an edit', () {
      const request = AiProviderConfigRequest(
        provider: AiProviderType.claude,
        model: 'CLAUDE_SONNET',
        apiKey: '   ',
      );

      expect(request.toJson().containsKey('apiKey'), isFalse);
      // The field the backend actually reads is aiProviderType, not provider —
      // the response spells it the other way round.
      expect(request.toJson()['aiProviderType'], 'CLAUDE');
    });

    test('a key that was typed is trimmed and sent', () {
      const request = AiProviderConfigRequest(
        provider: AiProviderType.openai,
        model: 'GPT_4O',
        apiKey: '  sk-test  ',
      );

      expect(request.toJson()['apiKey'], 'sk-test');
    });

    test('absent temperature and token cap are omitted, not nulled', () {
      const request = AiProviderConfigRequest(
        provider: AiProviderType.gemini,
        model: 'GEMINI_2_5_PRO',
      );

      expect(request.toJson().keys.toSet(), {'aiProviderType', 'model'});
    });
  });

  group('AiProviderType.modelsFor', () {
    test('every provider offers only its own models', () {
      for (final provider in AiProviderType.all) {
        expect(AiProviderType.modelsFor(provider), isNotEmpty);
      }
      expect(AiProviderType.modelsFor(AiProviderType.claude),
          isNot(contains('GPT_4O')));
      expect(AiProviderType.modelsFor(AiProviderType.openai),
          isNot(contains('CLAUDE_OPUS')));
    });

    test('an unknown provider still yields something selectable', () {
      expect(AiProviderType.modelsFor('SOMETHING_NEW'), isNotEmpty);
    });
  });

  group('AiUsageSummary', () {
    test('reads the per-feature maps and ignores anything malformed', () {
      final usage = AiUsageSummary.fromJson(const {
        'totalRequests': 12,
        'totalTokens': 4321,
        'avgResponseTimeMs': 812.5,
        'requestsByFeature': {'GENERAL': 8, 'LEAVE_POLICY': 4, 'bad': null},
        'tokensByFeature': {'GENERAL': 3000},
      });

      expect(usage.totalRequests, 12);
      expect(usage.requestsByFeature, {'GENERAL': 8, 'LEAVE_POLICY': 4});
      expect(usage.tokensByFeature['GENERAL'], 3000);
    });

    test('a missing map is empty rather than a crash', () {
      final usage = AiUsageSummary.fromJson(const {});
      expect(usage.requestsByFeature, isEmpty);
      expect(usage.avgResponseTimeMs, 0);
    });
  });

  group('DashboardSummary', () {
    test('a sparse response reads as zeroes rather than throwing', () {
      final summary = DashboardSummary.fromJson(const {'totalLeads': 5});

      expect(summary.totalLeads, 5);
      expect(summary.pipelineValue, 0);
      expect(summary.overdueInvoices, isEmpty);
      expect(summary.announcements, isEmpty);
    });

    test('nested lists are parsed', () {
      final summary = DashboardSummary.fromJson(const {
        'overdueInvoices': [
          {
            'invoiceNumber': 'INV-9',
            'clientName': 'Acme',
            'amount': 250.5,
            'daysOverdue': 12,
          },
          'not an object',
        ],
        'announcements': [
          {'title': 'Office closed', 'timeAgo': '2 days ago'},
        ],
      });

      expect(summary.overdueInvoices, hasLength(1));
      expect(summary.overdueInvoices.first.daysOverdue, 12);
      expect(summary.announcements.first.title, 'Office closed');
    });
  });

  group('Recommendation', () {
    test('severity drives which banner it gets', () {
      final critical =
          Recommendation.fromJson(const {'severity': 'CRITICAL', 'message': 'x'});
      final warning =
          Recommendation.fromJson(const {'severity': 'WARNING', 'message': 'x'});
      final plain = Recommendation.fromJson(const {'message': 'x'});

      expect(critical.isCritical, isTrue);
      expect(warning.isWarning, isTrue);
      // No severity at all falls back to INFO rather than being treated as
      // urgent.
      expect(plain.isCritical, isFalse);
      expect(plain.isWarning, isFalse);
      expect(plain.severity, 'INFO');
    });
  });

  group('SelfUpdateEmployeeRequest', () {
    test('a photo change sends only the photo', () {
      const request = SelfUpdateEmployeeRequest(
        profileImageUrl: 'https://files/avatar.png',
      );

      expect(request.toJson(), {'profileImageUrl': 'https://files/avatar.png'});
    });
  });
}
