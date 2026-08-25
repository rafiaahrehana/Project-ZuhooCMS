/// The service catalogue: what a client can ask for, and on what terms.
abstract final class CataloguePermissions {
  static const serviceView = 'SERVICE_CATALOG_VIEW';
  static const serviceCreate = 'SERVICE_CATALOG_CREATE';
  static const serviceUpdate = 'SERVICE_CATALOG_UPDATE';
  static const serviceDelete = 'SERVICE_CATALOG_DELETE';

  static const templateView = 'SERVICE_TEMPLATE_VIEW';
  static const templateCreate = 'SERVICE_TEMPLATE_CREATE';
  static const templateUpdate = 'SERVICE_TEMPLATE_UPDATE';
  static const templateDelete = 'SERVICE_TEMPLATE_DELETE';

  static const packageView = 'SERVICE_PACKAGE_VIEW';
}

/// How a service is priced. Mirrors `ServicePriceType`.
const servicePriceTypes = <String>[
  'FIXED',
  'HOURLY',
  'DAILY',
  'MONTHLY',
  'YEARLY',
  'CUSTOM',
];

/// Where a subscription stands. Mirrors `SubscriptionStatus`.
abstract final class SubscriptionStatus {
  static const active = 'ACTIVE';
  static const pendingPayment = 'PENDING_PAYMENT';
  static const expired = 'EXPIRED';
  static const suspended = 'SUSPENDED';
  static const cancelled = 'CANCELLED';

  /// Nothing more happens to a subscription in one of these.
  static const settled = {expired, cancelled};
}

/// A service in the company's catalogue, as the admin list shows it.
///
/// Deliberately a different class from `CatalogService` in the requests
/// module: that one is the short shape used when raising a request, and this
/// one carries the flags and pricing an administrator edits.
class ServiceListing {
  const ServiceListing({
    required this.id,
    required this.name,
    required this.active,
    this.description,
    this.price,
    this.priceType,
    this.estimatedDays,
    this.categoryId,
    this.categoryName,
    this.currency,
    this.featured = false,
    this.remote = false,
    this.onSite = false,
    this.online = false,
    this.autoApproval = false,
    this.requiresQuotation = false,
    this.requiresDocuments = false,
    this.supportsCustomWorkflow = false,
    this.aiAssisted = false,
  });

  final int id;
  final String name;
  final bool active;
  final String? description;
  final double? price;
  final String? priceType;
  final int? estimatedDays;
  final int? categoryId;
  final String? categoryName;
  final String? currency;

  /// The nine flags the update endpoint assigns **unconditionally**.
  ///
  /// They are primitive `boolean` on the DTO, so Jackson defaults each to
  /// false when the key is absent. An edit that omitted them would quietly
  /// switch all nine off — which is why they are parsed here and always sent
  /// back. See [ServiceListingRequest].
  final bool featured;
  final bool remote;
  final bool onSite;
  final bool online;
  final bool autoApproval;
  final bool requiresQuotation;
  final bool requiresDocuments;
  final bool supportsCustomWorkflow;
  final bool aiAssisted;

  /// How it is delivered, for the row's subtitle.
  String get deliveryLabel {
    final ways = [
      if (remote) 'Remote',
      if (onSite) 'On site',
      if (online) 'Online',
    ];
    return ways.isEmpty ? 'Delivery not set' : ways.join(' · ');
  }

  factory ServiceListing.fromJson(Map<String, dynamic> json) {
    bool b(String key) => json[key] as bool? ?? false;
    return ServiceListing(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      priceType: json['priceType'] as String?,
      estimatedDays: (json['estimatedDays'] as num?)?.toInt(),
      categoryId: (json['categoryId'] as num?)?.toInt(),
      categoryName: json['categoryName'] as String?,
      currency: json['currency'] as String?,
      featured: b('featured'),
      remote: b('remote'),
      onSite: b('onSite'),
      online: b('online'),
      autoApproval: b('autoApproval'),
      requiresQuotation: b('requiresQuotation'),
      requiresDocuments: b('requiresDocuments'),
      supportsCustomWorkflow: b('supportsCustomWorkflow'),
      aiAssisted: b('aiAssisted'),
    );
  }
}

/// POST and PUT /services
///
/// **All nine boolean flags go on every request.** They are primitives on the
/// DTO and assigned unconditionally by `CompanyServiceServiceImpl.update`, so
/// an omitted key arrives as `false` and turns the flag off. The edit form
/// seeds them from the service and posts all nine back, whether or not any
/// were touched.
///
/// The scalars are null-guarded server-side, so those are omitted when empty.
class ServiceListingRequest {
  const ServiceListingRequest({
    required this.name,
    required this.featured,
    required this.remote,
    required this.onSite,
    required this.online,
    required this.autoApproval,
    required this.requiresQuotation,
    required this.requiresDocuments,
    required this.supportsCustomWorkflow,
    required this.aiAssisted,
    this.description,
    this.price,
    this.priceType,
    this.estimatedDays,
    this.categoryId,
  });

  final String name;
  final bool featured;
  final bool remote;
  final bool onSite;
  final bool online;
  final bool autoApproval;
  final bool requiresQuotation;
  final bool requiresDocuments;
  final bool supportsCustomWorkflow;
  final bool aiAssisted;
  final String? description;
  final double? price;
  final String? priceType;
  final int? estimatedDays;
  final int? categoryId;

  factory ServiceListingRequest.from(ServiceListing service) =>
      ServiceListingRequest(
        name: service.name,
        featured: service.featured,
        remote: service.remote,
        onSite: service.onSite,
        online: service.online,
        autoApproval: service.autoApproval,
        requiresQuotation: service.requiresQuotation,
        requiresDocuments: service.requiresDocuments,
        supportsCustomWorkflow: service.supportsCustomWorkflow,
        aiAssisted: service.aiAssisted,
        description: service.description,
        price: service.price,
        priceType: service.priceType,
        estimatedDays: service.estimatedDays,
        categoryId: service.categoryId,
      );

  ServiceListingRequest copyWith({
    String? name,
    bool? featured,
    bool? remote,
    bool? onSite,
    bool? online,
    bool? autoApproval,
    bool? requiresQuotation,
    bool? requiresDocuments,
    bool? supportsCustomWorkflow,
    bool? aiAssisted,
    String? description,
    double? price,
    String? priceType,
    int? estimatedDays,
    int? categoryId,
  }) =>
      ServiceListingRequest(
        name: name ?? this.name,
        featured: featured ?? this.featured,
        remote: remote ?? this.remote,
        onSite: onSite ?? this.onSite,
        online: online ?? this.online,
        autoApproval: autoApproval ?? this.autoApproval,
        requiresQuotation: requiresQuotation ?? this.requiresQuotation,
        requiresDocuments: requiresDocuments ?? this.requiresDocuments,
        supportsCustomWorkflow:
            supportsCustomWorkflow ?? this.supportsCustomWorkflow,
        aiAssisted: aiAssisted ?? this.aiAssisted,
        description: description ?? this.description,
        price: price ?? this.price,
        priceType: priceType ?? this.priceType,
        estimatedDays: estimatedDays ?? this.estimatedDays,
        categoryId: categoryId ?? this.categoryId,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      // Unconditional, all nine: see the class comment.
      'featured': featured,
      'remote': remote,
      'onSite': onSite,
      'online': online,
      'autoApproval': autoApproval,
      'requiresQuotation': requiresQuotation,
      'requiresDocuments': requiresDocuments,
      'supportsCustomWorkflow': supportsCustomWorkflow,
      'aiAssisted': aiAssisted,
      if (clean(description) != null) 'description': clean(description),
      if (price != null) 'price': price,
      if (priceType != null) 'priceType': priceType,
      if (estimatedDays != null) 'estimatedDays': estimatedDays,
      if (categoryId != null) 'categoryId': categoryId,
    };
  }
}

/// A reusable service definition — the form fields, documents and workflow
/// stages a service is built from.
class ServiceTemplate {
  const ServiceTemplate({
    required this.id,
    required this.name,
    required this.active,
    this.description,
    this.defaultPrice,
    this.estimatedDays,
    this.categoryId,
    this.categoryName,
    this.formFieldCount = 0,
    this.requiredDocumentCount = 0,
    this.workflowStageCount = 0,
  });

  final int id;
  final String name;
  final bool active;
  final String? description;
  final double? defaultPrice;
  final int? estimatedDays;
  final int? categoryId;
  final String? categoryName;

  /// Counts only. The lists themselves are composed on the web — a repeater of
  /// form fields inside a repeater of stages is not a phone form — and the
  /// update endpoint leaves them alone when they are not sent.
  final int formFieldCount;
  final int requiredDocumentCount;
  final int workflowStageCount;

  factory ServiceTemplate.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as List?)?.length ?? 0;
    return ServiceTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      description: json['description'] as String?,
      defaultPrice: (json['defaultPrice'] as num?)?.toDouble(),
      estimatedDays: (json['estimatedDays'] as num?)?.toInt(),
      categoryId: (json['categoryId'] as num?)?.toInt(),
      categoryName: json['categoryName'] as String?,
      formFieldCount: count('formFields'),
      requiredDocumentCount: count('requiredDocuments'),
      workflowStageCount: count('workflowStages'),
    );
  }
}

/// POST and PUT /v1/service-templates
///
/// `categoryId` carries no `@NotNull`, but `create` looks the category up
/// without checking for null first — a template posted without one fails in
/// the data layer rather than validation. The form treats it as required, and
/// says so when there are no categories to pick from.
///
/// `active` is a primitive on the DTO and assigned unconditionally, so it
/// always goes.
///
/// The three nested lists — form fields, required documents, workflow stages —
/// are deliberately never sent. `update` does not touch them unless they are
/// present, so omitting them preserves whatever the web editor built.
class ServiceTemplateRequest {
  const ServiceTemplateRequest({
    required this.name,
    required this.active,
    this.description,
    this.defaultPrice,
    this.estimatedDays,
    this.categoryId,
  });

  final String name;
  final bool active;
  final String? description;
  final double? defaultPrice;
  final int? estimatedDays;
  final int? categoryId;

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    return {
      'name': name.trim(),
      'active': active,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
      if (defaultPrice != null) 'defaultPrice': defaultPrice,
      if (estimatedDays != null) 'estimatedDays': estimatedDays,
      if (categoryId != null) 'categoryId': categoryId,
      // No formFields / requiredDocuments / workflowStages: see the comment.
    };
  }
}

/// A bundle of services sold on a cycle.
class ServicePackage {
  const ServicePackage({
    required this.id,
    required this.name,
    required this.active,
    this.description,
    this.packagePrice,
    this.effectivePrice,
    this.discountPercent,
    this.billingCycle,
    this.requestQuota,
    this.deliveryDays,
    this.featured = false,
    this.popular = false,
  });

  final int id;
  final String name;
  final bool active;
  final String? description;

  /// What was set by hand, if anything.
  final double? packagePrice;

  /// What a client actually pays — the manual price if set, else the sum of
  /// the bundled services with the discount applied. Computed server-side.
  final double? effectivePrice;

  final double? discountPercent;
  final String? billingCycle;
  final int? requestQuota;
  final int? deliveryDays;
  final bool featured;
  final bool popular;

  factory ServicePackage.fromJson(Map<String, dynamic> json) => ServicePackage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        packagePrice: (json['packagePrice'] as num?)?.toDouble(),
        effectivePrice: (json['effectivePrice'] as num?)?.toDouble(),
        discountPercent: (json['discountPercent'] as num?)?.toDouble(),
        billingCycle: json['billingCycle'] as String?,
        requestQuota: (json['requestQuota'] as num?)?.toInt(),
        deliveryDays: (json['deliveryDays'] as num?)?.toInt(),
        featured: json['featured'] as bool? ?? false,
        popular: json['popular'] as bool? ?? false,
      );
}

/// One client's subscription to a package.
class PackageSubscription {
  const PackageSubscription({
    required this.id,
    required this.status,
    required this.requestsUsed,
    required this.remainingRequests,
    this.packageName,
    this.clientName,
    this.billingCycle,
    this.startDate,
    this.endDate,
    this.nextBillingDate,
    this.pricePaid,
    this.requestQuota,
  });

  final int id;
  final String status;
  final int requestsUsed;
  final int remainingRequests;
  final String? packageName;
  final String? clientName;
  final String? billingCycle;
  final String? startDate;
  final String? endDate;
  final String? nextBillingDate;
  final double? pricePaid;
  final int? requestQuota;

  bool get isActive => status == SubscriptionStatus.active;
  bool get isSuspended => status == SubscriptionStatus.suspended;

  /// Nothing more will happen to it, so the row offers no actions.
  bool get isSettled => SubscriptionStatus.settled.contains(status);

  /// How much of the allowance is gone, or null when it is unlimited — an
  /// empty bar would read as "none used" rather than "no limit".
  double? get usage {
    final quota = requestQuota;
    if (quota == null || quota <= 0) return null;
    return (requestsUsed / quota).clamp(0.0, 1.0);
  }

  factory PackageSubscription.fromJson(Map<String, dynamic> json) =>
      PackageSubscription(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? SubscriptionStatus.pendingPayment,
        requestsUsed: (json['requestsUsed'] as num?)?.toInt() ?? 0,
        remainingRequests: (json['remainingRequests'] as num?)?.toInt() ?? 0,
        packageName: json['packageName'] as String?,
        clientName: json['clientName'] as String?,
        billingCycle: json['billingCycle'] as String?,
        startDate: json['startDate'] as String?,
        endDate: json['endDate'] as String?,
        nextBillingDate: json['nextBillingDate'] as String?,
        pricePaid: (json['pricePaid'] as num?)?.toDouble(),
        requestQuota: (json['requestQuota'] as num?)?.toInt(),
      );
}
