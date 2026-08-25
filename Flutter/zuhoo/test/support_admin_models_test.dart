import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/support_admin/support_admin_models.dart';

/// Every PATCH on the support desk assigns its fields with no null check, and
/// several of them are Java primitives with non-zero defaults. An omitted key
/// therefore does not preserve a value — it replaces it with the default. These
/// tests pin what has to be on the wire.
void main() {
  group('SupportAgentRequest', () {
    test('always sends the ticket limit', () {
      // maxConcurrentTickets is `private int ... = 10`, so an absent key leaves
      // the Java default and silently rewrites the agent's limit to 10.
      final json = const SupportAgentRequest(maxConcurrentTickets: 3).toJson();
      expect(json.containsKey('maxConcurrentTickets'), isTrue);
      expect(json['maxConcurrentTickets'], 3);
    });

    test('sends the free-text fields as null rather than omitting them', () {
      // They are assigned unconditionally either way, so an explicit null is
      // the honest representation of "cleared".
      final json = const SupportAgentRequest(maxConcurrentTickets: 5).toJson();
      for (final key in ['department', 'specialization', 'notes']) {
        expect(json.containsKey(key), isTrue, reason: '$key must be present');
        expect(json[key], isNull);
      }
    });

    test('leaves userId out on an edit, where it means nothing', () {
      expect(
        const SupportAgentRequest(maxConcurrentTickets: 5).toJson()
            .containsKey('userId'),
        isFalse,
      );
      expect(
        const SupportAgentRequest(maxConcurrentTickets: 5, userId: 12)
            .toJson()['userId'],
        12,
      );
    });

    test('carries the whole record over from the agent being edited', () {
      const agent = SupportAgent(
        id: 1,
        status: 'ACTIVE',
        acceptingTickets: true,
        maxConcurrentTickets: 25,
        totalTicketsHandled: 400,
        department: 'Billing',
        specialization: 'Refunds',
        notes: 'Prefers written handovers.',
      );

      final json = SupportAgentRequest.from(agent).toJson();
      expect(json['maxConcurrentTickets'], 25);
      expect(json['department'], 'Billing');
      expect(json['specialization'], 'Refunds');
      expect(json['notes'], 'Prefers written handovers.');
    });
  });

  group('SupportAgent', () {
    SupportAgent agent({String status = 'ACTIVE', bool accepting = true}) =>
        SupportAgent(
          id: 1,
          status: status,
          acceptingTickets: accepting,
          maxConcurrentTickets: 10,
          totalTicketsHandled: 0,
        );

    test('needs both conditions to be taking work', () {
      expect(agent().isTakingWork, isTrue);
      // Marked active but has turned new tickets off.
      expect(agent(accepting: false).isTakingWork, isFalse);
      expect(agent(status: 'ON_BREAK').isTakingWork, isFalse);
    });

    test('falls back through the name fields the backend might send', () {
      expect(
        SupportAgent.fromJson(const {
          'id': 1,
          'userName': 'a.khan',
          'email': 'a@example.com',
        }).displayName,
        'a.khan',
      );
      expect(
        SupportAgent.fromJson(const {'id': 2, 'email': 'b@example.com'})
            .displayName,
        'b@example.com',
      );
      expect(SupportAgent.fromJson(const {'id': 3}).displayName, 'Agent 3');
    });
  });

  group('SupportCategory', () {
    test('reads categoryName, which is what the backend calls it', () {
      final category = SupportCategory.fromJson(const {
        'id': 1,
        'categoryName': 'Billing',
        'active': false,
      });
      expect(category.name, 'Billing');
      expect(category.active, isFalse);
    });

    test('sends categoryName back, and never touches active', () {
      // The update ignores `active` entirely — it has its own endpoint — and
      // on create the DTO's own default of true is the right answer, so the
      // key stays off the wire either way.
      final json = const SupportCategoryRequest(name: ' Billing ').toJson();
      expect(json['categoryName'], 'Billing');
      expect(json.containsKey('active'), isFalse);
    });
  });

  group('SlaPolicyRequest', () {
    const request = SlaPolicyRequest(
      name: 'Critical response',
      priority: 'CRITICAL',
      firstResponseTimeHours: 1,
      resolutionTimeHours: 4,
      businessHoursOnly: false,
      active: true,
    );

    test('always sends both hour counts', () {
      // Primitive ints assigned unconditionally: an omitted key arrives as
      // zero, which promises an instant reply.
      final json = request.toJson();
      expect(json['firstResponseTimeHours'], 1);
      expect(json['resolutionTimeHours'], 4);
    });

    test('always sends both flags', () {
      final json = request.toJson();
      expect(json['businessHoursOnly'], isFalse);
      expect(json['active'], isTrue);
    });

    test('maps onto the backend field names', () {
      final json = request.toJson();
      expect(json['policyName'], 'Critical response');
      expect(json['applicablePriority'], 'CRITICAL');
    });

    test('omits notes when there are none', () {
      expect(request.toJson().containsKey('notes'), isFalse);
    });
  });

  group('AuditFilter', () {
    test('a half-finished date range is not a range', () {
      expect(const AuditFilter(start: '2026-01-01').hasDateRange, isFalse);
      expect(
        const AuditFilter(start: '2026-01-01', end: '2026-01-31').hasDateRange,
        isTrue,
      );
    });

    test('knows when nothing is set', () {
      expect(const AuditFilter().isEmpty, isTrue);
      expect(const AuditFilter(actionType: 'TICKET_ASSIGNED').isEmpty, isFalse);
    });
  });
}
