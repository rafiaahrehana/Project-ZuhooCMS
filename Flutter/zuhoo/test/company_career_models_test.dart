import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/company/company_models.dart';
import 'package:zuhoo/features/crm/crm_models.dart';
import 'package:zuhoo/features/platform/platform_models.dart';
import 'package:zuhoo/features/recruitment/career_page_screen.dart';
import 'package:zuhoo/features/recruitment/recruitment_models.dart';

void main() {
  group('CompanyProfileRequest', () {
    test('omits what was not set, because the backend null-checks each field',
        () {
      const request = CompanyProfileRequest(companyPhone: '0500000000');
      expect(request.toJson(), {'companyPhone': '0500000000'});
    });

    test('has no field for the subdomain or the registered email', () {
      const request = CompanyProfileRequest(
        companyName: 'Acme',
        website: 'acme.test',
      );
      final json = request.toJson();

      // Neither is on the update DTO at all. If either ever appears here, the
      // screen has started offering something the backend will ignore.
      expect(json.containsKey('subdomain'), isFalse);
      expect(json.containsKey('companyEmail'), isFalse);
    });
  });

  group('CareerPageSettings', () {
    test('a save sends every field, since the PUT assigns them all', () {
      const settings = CareerPageSettings(slug: 'acme', published: true);
      final json = settings.toJson();

      expect(json.keys.toSet(), {
        'slug',
        'published',
        'headline',
        'about',
        'brandColor',
      });
      // Present and null rather than absent — the backend writes what it is
      // sent without a null check, so there is no "leave it alone".
      expect(json['headline'], isNull);
    });

    test('copyWith keeps the fields the form does not show', () {
      const settings = CareerPageSettings(
        slug: 'acme',
        published: false,
        brandColor: '#123456',
      );

      final json = settings.copyWith(published: true).toJson();
      expect(json['brandColor'], '#123456');
      expect(json['published'], isTrue);
    });
  });

  group('JobApplicationRequest', () {
    test('sends only what was filled in', () {
      const request = JobApplicationRequest(
        applicantName: '  Sara  ',
        applicantEmail: '  sara@example.test ',
        applicantPhone: '   ',
        source: 'EMPLOYEE_REFERRAL',
      );
      final json = request.toJson();

      expect(json['applicantName'], 'Sara');
      expect(json['applicantEmail'], 'sara@example.test');
      // A box left blank is not a phone number of spaces.
      expect(json.containsKey('applicantPhone'), isFalse);
      expect(json['source'], 'EMPLOYEE_REFERRAL');
    });
  });

  group('SubscriptionPlanOption', () {
    test('reads the row id, which is not the plan code', () {
      final plan = SubscriptionPlanOption.fromJson(const {
        'id': 7,
        'code': 'PRO',
        'name': 'Professional',
        'price': 499.0,
        'billingCycle': 'MONTHLY',
        'active': false,
      });

      expect(plan.id, 7);
      // The code is what a company stores; the id is what the write endpoints
      // key on. Confusing the two would edit the wrong row.
      expect(plan.key, 'PRO');
      expect(plan.active, isFalse);
    });

    test('a response without an id still yields a usable picker entry', () {
      final plan = SubscriptionPlanOption.fromJson(const {
        'planKey': 'FREE',
        'name': 'Free',
      });

      expect(plan.key, 'FREE');
      expect(plan.id, isNull);
      // Defaults to on: a plan the server offered without saying otherwise is
      // one that can be sold.
      expect(plan.active, isTrue);
    });
  });

  group('LeadFilter', () {
    test('a default filter narrows nothing', () {
      expect(const LeadFilter().isEmpty, isTrue);
      expect(const LeadFilter(keyword: '   ').isEmpty, isTrue);
      expect(const LeadFilter(isUnassigned: true).isEmpty, isFalse);
      expect(const LeadFilter(sortDirection: 'ASC').isEmpty, isFalse);
    });

    test('clearing a choice is distinct from leaving it alone', () {
      const filter = LeadFilter(status: 'NEW', source: 'WEBSITE');

      expect(filter.copyWith(clearStatus: true).status, isNull);
      // Clearing one must not clear the other.
      expect(filter.copyWith(clearStatus: true).source, 'WEBSITE');
    });

    test('the sort is always sent, since the backend has a default of its own',
        () {
      final json = const LeadFilter().toJson();
      expect(json['sortBy'], 'createdAt');
      expect(json['sortDirection'], 'DESC');
      expect(json.containsKey('keyword'), isFalse);
    });
  });
}
