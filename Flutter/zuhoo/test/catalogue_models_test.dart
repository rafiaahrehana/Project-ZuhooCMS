import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/catalogue/catalogue_models.dart';
import 'package:zuhoo/features/requests/request_models.dart'
    show CreateServicePackageRequest;

/// The catalogue's update endpoints assign several fields unconditionally, so
/// a request that leaves one out does not preserve it — it clears it. These
/// tests pin the fields that have to go on every request, because getting one
/// wrong silently turns something off in production rather than failing.
void main() {
  group('ServiceListingRequest', () {
    const allOff = ServiceListingRequest(
      name: 'Company formation',
      featured: false,
      remote: false,
      onSite: false,
      online: false,
      autoApproval: false,
      requiresQuotation: false,
      requiresDocuments: false,
      supportsCustomWorkflow: false,
      aiAssisted: false,
    );

    test('sends all nine flags even when every one is false', () {
      final json = allOff.toJson();
      for (final key in [
        'featured',
        'remote',
        'onSite',
        'online',
        'autoApproval',
        'requiresQuotation',
        'requiresDocuments',
        'supportsCustomWorkflow',
        'aiAssisted',
      ]) {
        expect(
          json.containsKey(key),
          isTrue,
          reason: '$key is a primitive boolean on the DTO and is assigned '
              'unconditionally — omitting it turns it off',
        );
        expect(json[key], isFalse);
      }
    });

    test('omits the null-guarded scalars rather than clearing them', () {
      final json = allOff.toJson();
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('price'), isFalse);
      expect(json.containsKey('estimatedDays'), isFalse);
      expect(json.containsKey('categoryId'), isFalse);
    });

    test('an empty description is treated as absent, not as a blank', () {
      expect(allOff.copyWith(description: '   ').toJson()['description'], null);
      expect(
        allOff.copyWith(description: '   ').toJson().containsKey('description'),
        isFalse,
      );
    });

    test('carries every flag over from the service being edited', () {
      const service = ServiceListing(
        id: 7,
        name: 'Audit',
        active: true,
        categoryId: 3,
        price: 500,
        priceType: 'FIXED',
        estimatedDays: 5,
        featured: true,
        remote: true,
        onSite: false,
        online: true,
        autoApproval: true,
        requiresQuotation: false,
        requiresDocuments: true,
        supportsCustomWorkflow: true,
        aiAssisted: false,
      );

      final json = ServiceListingRequest.from(service).toJson();
      expect(json['featured'], isTrue);
      expect(json['remote'], isTrue);
      expect(json['onSite'], isFalse);
      expect(json['online'], isTrue);
      expect(json['autoApproval'], isTrue);
      expect(json['requiresQuotation'], isFalse);
      expect(json['requiresDocuments'], isTrue);
      expect(json['supportsCustomWorkflow'], isTrue);
      expect(json['aiAssisted'], isFalse);
      expect(json['categoryId'], 3);
    });
  });

  group('ServiceListing.fromJson', () {
    test('reads the flags, defaulting each to off when absent', () {
      final service = ServiceListing.fromJson(const {
        'id': 2,
        'name': 'Trade licence',
        'active': true,
        'remote': true,
        'requiresDocuments': true,
      });

      expect(service.remote, isTrue);
      expect(service.requiresDocuments, isTrue);
      expect(service.featured, isFalse);
      expect(service.aiAssisted, isFalse);
    });

    test('names how it is delivered, and says so when nothing is set', () {
      expect(
        ServiceListing.fromJson(const {
          'id': 1,
          'name': 'x',
          'remote': true,
          'online': true,
        }).deliveryLabel,
        'Remote · Online',
      );
      expect(
        ServiceListing.fromJson(const {'id': 1, 'name': 'x'}).deliveryLabel,
        'Delivery not set',
      );
    });
  });

  group('ServiceTemplateRequest', () {
    test('always sends active — it is a primitive on the DTO', () {
      final json =
          const ServiceTemplateRequest(name: 'Onboarding', active: false)
              .toJson();
      expect(json.containsKey('active'), isTrue);
      expect(json['active'], isFalse);
    });

    test('never sends the nested lists, so the web editor keeps its work', () {
      final json =
          const ServiceTemplateRequest(name: 'Onboarding', active: true)
              .toJson();
      expect(json.containsKey('formFields'), isFalse);
      expect(json.containsKey('requiredDocuments'), isFalse);
      expect(json.containsKey('workflowStages'), isFalse);
    });
  });

  group('ServiceTemplate.fromJson', () {
    test('counts the nested lists rather than parsing them', () {
      final template = ServiceTemplate.fromJson(const {
        'id': 4,
        'name': 'Company formation',
        'active': true,
        'categoryId': 2,
        'formFields': [{}, {}, {}],
        'workflowStages': [{}],
      });

      expect(template.formFieldCount, 3);
      expect(template.workflowStageCount, 1);
      expect(template.requiredDocumentCount, 0);
      expect(template.categoryId, 2);
    });
  });

  group('CreateServicePackageRequest', () {
    const request = CreateServicePackageRequest(
      name: 'Starter',
      billingCycle: 'MONTHLY',
    );

    test('always sends the four unconditional fields', () {
      final json = request.toJson();
      // packagePrice and discountPercent are assigned without a null check, and
      // featured/popular are primitives — all four have to be present.
      expect(json.containsKey('packagePrice'), isTrue);
      expect(json.containsKey('discountPercent'), isTrue);
      expect(json['featured'], isFalse);
      expect(json['popular'], isFalse);
    });

    test('a null price is sent explicitly, which clears a manual override', () {
      expect(request.toJson()['packagePrice'], isNull);
    });

    test('keeps the bundle when no services are given', () {
      // serviceIds is null-guarded server-side: omitting it preserves what is
      // bundled, which is why an empty list must not be sent as one.
      expect(request.toJson().containsKey('serviceIds'), isFalse);
      expect(
        const CreateServicePackageRequest(
          name: 'Starter',
          billingCycle: 'MONTHLY',
          serviceIds: [1, 2],
        ).toJson()['serviceIds'],
        [1, 2],
      );
    });
  });

  group('PackageSubscription', () {
    PackageSubscription subscription({int? quota, int used = 0, String? status}) =>
        PackageSubscription(
          id: 1,
          status: status ?? SubscriptionStatus.active,
          requestsUsed: used,
          remainingRequests: (quota ?? 0) - used,
          requestQuota: quota,
        );

    test('has no usage figure when the allowance is unlimited', () {
      // An empty bar would read as "none used" rather than "no limit".
      expect(subscription().usage, isNull);
      expect(subscription(quota: 0).usage, isNull);
    });

    test('clamps usage rather than overflowing the bar', () {
      expect(subscription(quota: 10, used: 4).usage, 0.4);
      expect(subscription(quota: 10, used: 14).usage, 1.0);
    });

    test('knows which states still have actions left', () {
      expect(subscription(status: SubscriptionStatus.cancelled).isSettled,
          isTrue);
      expect(
          subscription(status: SubscriptionStatus.expired).isSettled, isTrue);
      expect(subscription(status: SubscriptionStatus.suspended).isSettled,
          isFalse);
      expect(subscription(status: SubscriptionStatus.pendingPayment).isSettled,
          isFalse);
    });
  });
}
