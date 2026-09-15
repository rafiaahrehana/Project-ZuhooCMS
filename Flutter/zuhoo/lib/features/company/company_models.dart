/// The company you work for, as it sees itself.
///
/// Distinct from the platform module's [Company], which is how the people who
/// run the platform see a tenant — status, plan, owner. This is the tenant's
/// own record of itself: contact details, banking, the fiscal year, and what
/// its portal shows to clients.
library;

abstract final class CompanyPermissions {
  /// The three the backend accepts for editing the record — any one will do,
  /// so all three are named here and the UI asks for the same set.
  static const update = 'COMPANY_UPDATE';
  static const settings = 'COMPANY_SETTINGS';
  static const branding = 'COMPANY_BRANDING';

  static const editAny = [update, settings, branding];
}

class CompanyProfile {
  const CompanyProfile({
    required this.id,
    required this.companyName,
    this.subdomain,
    this.companyEmail,
    this.companyPhone,
    this.website,
    this.location,
    this.logo,
    this.primaryColor,
    this.secondaryColor,
    this.tagline,
    this.portalAbout,
    this.taxRegistrationNumber,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankBranch,
    this.fiscalYearStartMonth,
    this.baseCurrency,
    this.status,
    this.subscriptionPlan,
    this.subscriptionStart,
    this.subscriptionEnd,
    this.trialExpired = false,
    this.ownerName,
    this.ownerEmail,
    this.createdAt,
  });

  final int id;
  final String companyName;

  /// The name in the portal address. Set once at registration and not
  /// editable — changing it would break every link a client has.
  final String? subdomain;

  final String? companyEmail;
  final String? companyPhone;
  final String? website;
  final String? location;

  /// Branding. These three live on a separate WebsiteSettings record
  /// server-side and are folded into this response, which is why they can be
  /// set here but do not appear on the company row itself.
  final String? logo;
  final String? primaryColor;
  final String? secondaryColor;
  final String? tagline;

  /// What the client portal says about the company.
  final String? portalAbout;

  final String? taxRegistrationNumber;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankBranch;

  /// 1 to 12. The backend rejects anything outside that rather than clamping.
  final int? fiscalYearStartMonth;

  final String? baseCurrency;

  /// Set by the platform, not by the company. Shown, never edited here.
  final String? status;
  final String? subscriptionPlan;
  final String? subscriptionStart;
  final String? subscriptionEnd;
  final bool trialExpired;

  final String? ownerName;
  final String? ownerEmail;
  final String? createdAt;

  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        companyName: json['companyName'] as String? ?? '',
        subdomain: json['subdomain'] as String?,
        companyEmail: json['companyEmail'] as String?,
        companyPhone: json['companyPhone'] as String?,
        website: json['website'] as String?,
        location: json['location'] as String?,
        logo: json['logo'] as String?,
        primaryColor: json['primaryColor'] as String?,
        secondaryColor: json['secondaryColor'] as String?,
        tagline: json['tagline'] as String?,
        portalAbout: json['portalAbout'] as String?,
        taxRegistrationNumber: json['taxRegistrationNumber'] as String?,
        bankName: json['bankName'] as String?,
        bankAccountName: json['bankAccountName'] as String?,
        bankAccountNumber: json['bankAccountNumber'] as String?,
        bankBranch: json['bankBranch'] as String?,
        fiscalYearStartMonth: (json['fiscalYearStartMonth'] as num?)?.toInt(),
        baseCurrency: json['baseCurrency'] as String?,
        status: json['status'] as String?,
        subscriptionPlan: json['subscriptionPlan'] as String?,
        subscriptionStart: json['subscriptionStart'] as String?,
        subscriptionEnd: json['subscriptionEnd'] as String?,
        trialExpired: json['trialExpired'] as bool? ?? false,
        ownerName: json['ownerName'] as String?,
        ownerEmail: json['ownerEmail'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

/// Changing the company's own record.
///
/// A real patch, unusually for this backend: `CompanyServiceImpl.update`
/// null-checks every field, so omitting one leaves it alone. Only what a form
/// actually changed needs sending.
///
/// Two things it cannot touch: the subdomain and the email the company
/// registered with. Neither is on the request DTO at all.
class CompanyProfileRequest {
  const CompanyProfileRequest({
    this.companyName,
    this.companyPhone,
    this.website,
    this.portalAbout,
    this.logo,
    this.primaryColor,
    this.secondaryColor,
    this.tagline,
    this.taxRegistrationNumber,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankBranch,
    this.fiscalYearStartMonth,
    this.baseCurrency,
  });

  final String? companyName;
  final String? companyPhone;
  final String? website;
  final String? portalAbout;
  final String? logo;
  final String? primaryColor;
  final String? secondaryColor;
  final String? tagline;
  final String? taxRegistrationNumber;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankBranch;

  /// 1 to 12, or the backend refuses with a message rather than clamping.
  final int? fiscalYearStartMonth;

  /// Upper-cased and trimmed server-side, and a blank one is ignored rather
  /// than clearing what is set — there is no such thing as no currency.
  final String? baseCurrency;

  Map<String, dynamic> toJson() => {
        if (companyName != null) 'companyName': companyName,
        if (companyPhone != null) 'companyPhone': companyPhone,
        if (website != null) 'website': website,
        if (portalAbout != null) 'portalAbout': portalAbout,
        if (logo != null) 'logo': logo,
        if (primaryColor != null) 'primaryColor': primaryColor,
        if (secondaryColor != null) 'secondaryColor': secondaryColor,
        if (tagline != null) 'tagline': tagline,
        if (taxRegistrationNumber != null)
          'taxRegistrationNumber': taxRegistrationNumber,
        if (bankName != null) 'bankName': bankName,
        if (bankAccountName != null) 'bankAccountName': bankAccountName,
        if (bankAccountNumber != null) 'bankAccountNumber': bankAccountNumber,
        if (bankBranch != null) 'bankBranch': bankBranch,
        if (fiscalYearStartMonth != null)
          'fiscalYearStartMonth': fiscalYearStartMonth,
        if (baseCurrency != null) 'baseCurrency': baseCurrency,
      };
}

/// POST /payments/sslcommerz/initiate, for the one purpose this app starts a
/// checkout for. The other three ([GatewayPurpose] values the backend also
/// accepts — an invoice, a wallet top-up, a service package) stay web-only for
/// now; this is scoped to what [SubscriptionPlanScreen] actually needs.
///
/// The amount is sent for `@NotNull`/`@DecimalMin` shape only — the service
/// never trusts a client-supplied price for a plan upgrade and re-derives it
/// from the plan's own catalog row before charging anything.
class SubscriptionUpgradeRequest {
  const SubscriptionUpgradeRequest({required this.planId, required this.amount});

  final int planId;
  final double amount;

  Map<String, dynamic> toJson() => {
        'purpose': 'PLATFORM_SUBSCRIPTION',
        'targetId': planId,
        'amount': amount,
      };
}

/// A company as anybody on the internet sees it, before signing in.
///
/// Deliberately thin: the public endpoints are unauthenticated, so what they
/// return is only what a company has chosen to put on its own portal page.
class PublicCompany {
  const PublicCompany({
    required this.companyName,
    this.subdomain,
    this.logo,
    this.tagline,
    this.portalAbout,
    this.website,
    this.primaryColor,
    this.secondaryColor,
  });

  final String companyName;
  final String? subdomain;
  final String? logo;
  final String? tagline;
  final String? portalAbout;
  final String? website;
  final String? primaryColor;
  final String? secondaryColor;

  factory PublicCompany.fromJson(Map<String, dynamic> json) => PublicCompany(
        companyName: json['companyName'] as String? ?? '',
        subdomain: json['subdomain'] as String?,
        logo: json['logo'] as String? ?? json['logoUrl'] as String?,
        tagline: json['tagline'] as String?,
        portalAbout: json['portalAbout'] as String? ?? json['about'] as String?,
        website: json['website'] as String?,
        primaryColor: json['primaryColor'] as String?,
        secondaryColor: json['secondaryColor'] as String?,
      );
}
