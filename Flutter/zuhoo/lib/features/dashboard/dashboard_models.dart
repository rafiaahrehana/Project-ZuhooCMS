/// The dashboard: one call that counts everything, and the two smaller calls
/// that interpret it.
///
/// `DashboardSummaryResponse` is a wide, flat DTO — fifty-odd fields covering
/// CRM, the service desk, support, finance and HR. This models the ones a
/// phone can show usefully; the rest belong to the web dashboard's charts.
library;

/// What the company looks like right now.
class DashboardSummary {
  const DashboardSummary({
    required this.totalLeads,
    required this.newLeads,
    required this.qualifiedLeads,
    required this.totalClients,
    required this.openOpportunities,
    required this.pipelineValue,
    required this.weightedForecast,
    required this.pendingRequests,
    required this.inProgressRequests,
    required this.slaBreachedOpen,
    required this.openTickets,
    required this.newTickets,
    required this.outstandingInvoiceAmount,
    required this.walletBalance,
    required this.totalEmployees,
    required this.pendingLeaveApprovals,
    required this.employeesPresentToday,
    required this.employeesOnLeave,
    required this.leadsTrend,
    required this.clientsTrend,
    required this.opportunitiesTrend,
    required this.overdueInvoices,
    required this.announcements,
  });

  // CRM
  final int totalLeads;
  final int newLeads;
  final int qualifiedLeads;
  final int totalClients;
  final int openOpportunities;
  final double pipelineValue;

  /// The pipeline discounted by each opportunity's probability. Always the
  /// smaller of the two, and the one worth planning against.
  final double weightedForecast;

  // The service desk
  final int pendingRequests;
  final int inProgressRequests;
  final int slaBreachedOpen;

  // Support
  final int openTickets;
  final int newTickets;

  // Finance
  final double outstandingInvoiceAmount;
  final double walletBalance;

  // People
  final int totalEmployees;
  final int pendingLeaveApprovals;
  final int employeesPresentToday;
  final int employeesOnLeave;

  /// Percentages against the previous period. A `double`, and zero both when
  /// nothing moved and when there is nothing to compare against — the backend
  /// does not distinguish the two.
  final double leadsTrend;
  final double clientsTrend;
  final double opportunitiesTrend;

  final List<OverdueInvoice> overdueInvoices;
  final List<DashboardAnnouncement> announcements;

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;
  static double _double(Object? value) => (value as num?)?.toDouble() ?? 0;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalLeads: _int(json['totalLeads']),
        newLeads: _int(json['newLeads']),
        qualifiedLeads: _int(json['qualifiedLeads']),
        totalClients: _int(json['totalClients']),
        openOpportunities: _int(json['openOpportunities']),
        pipelineValue: _double(json['pipelineValue']),
        weightedForecast: _double(json['weightedForecast']),
        pendingRequests: _int(json['pendingRequests']),
        inProgressRequests: _int(json['inProgressRequests']),
        slaBreachedOpen: _int(json['slaBreachedOpen']),
        openTickets: _int(json['openTickets']),
        newTickets: _int(json['newTickets']),
        outstandingInvoiceAmount: _double(json['outstandingInvoiceAmount']),
        walletBalance: _double(json['walletBalance']),
        totalEmployees: _int(json['totalEmployees']),
        pendingLeaveApprovals: _int(json['pendingLeaveApprovals']),
        employeesPresentToday: _int(json['employeesPresentToday']),
        employeesOnLeave: _int(json['employeesOnLeave']),
        leadsTrend: _double(json['leadsTrend']),
        clientsTrend: _double(json['clientsTrend']),
        opportunitiesTrend: _double(json['opportunitiesTrend']),
        overdueInvoices: (json['overdueInvoices'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OverdueInvoice.fromJson)
            .toList(growable: false),
        announcements:
            (json['announcements'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(DashboardAnnouncement.fromJson)
                .toList(growable: false),
      );
}

class OverdueInvoice {
  const OverdueInvoice({
    required this.invoiceNumber,
    required this.amount,
    required this.daysOverdue,
    this.clientName,
  });

  final String invoiceNumber;
  final double amount;
  final int daysOverdue;
  final String? clientName;

  factory OverdueInvoice.fromJson(Map<String, dynamic> json) => OverdueInvoice(
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
        clientName: json['clientName'] as String?,
      );
}

/// The dashboard's own cut of an announcement — a title, the text, and how
/// long ago in words. No id, so there is nothing to open.
class DashboardAnnouncement {
  const DashboardAnnouncement({
    required this.title,
    this.content,
    this.timeAgo,
  });

  final String title;
  final String? content;
  final String? timeAgo;

  factory DashboardAnnouncement.fromJson(Map<String, dynamic> json) =>
      DashboardAnnouncement(
        title: json['title'] as String? ?? '',
        content: json['content'] as String?,
        timeAgo: json['timeAgo'] as String?,
      );
}

/// Something the system thinks is worth doing.
class Recommendation {
  const Recommendation({
    required this.type,
    required this.severity,
    required this.message,
    this.link,
  });

  /// FOLLOW_UP, SLA_RISK, LICENSE_EXPIRY or OVERDUE_INVOICE.
  final String type;

  /// INFO, WARNING or CRITICAL.
  final String severity;

  final String message;

  /// An Angular route. Kept because it says which part of the product the
  /// recommendation is about, but not followed — the paths are the web app's
  /// and mean nothing to this one.
  final String? link;

  bool get isCritical => severity == 'CRITICAL';
  bool get isWarning => severity == 'WARNING';

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        type: json['type'] as String? ?? '',
        severity: json['severity'] as String? ?? 'INFO',
        message: json['message'] as String? ?? '',
        link: json['link'] as String?,
      );
}

/// The assistant's read on the numbers above.
class DashboardInsights {
  const DashboardInsights({required this.insights, this.generatedInMs = 0});

  final String insights;
  final int generatedInMs;

  factory DashboardInsights.fromJson(Map<String, dynamic> json) =>
      DashboardInsights(
        insights: json['insights'] as String? ?? '',
        generatedInMs: (json['generatedInMs'] as num?)?.toInt() ?? 0,
      );
}

// ── The platform's own dashboard ──────────────────────────────

/// Every tenant, seen from the outside. Platform staff only.
class PlatformSummary {
  const PlatformSummary({
    required this.totalCompanies,
    required this.activeCompanies,
    required this.trialCompanies,
    required this.suspendedCompanies,
    required this.pendingVerificationCompanies,
    required this.trialsExpiringWithin7Days,
    required this.totalPlatformUsers,
    required this.totalRevenue,
    required this.revenueThisMonth,
    required this.companiesByPlan,
  });

  final int totalCompanies;
  final int activeCompanies;
  final int trialCompanies;
  final int suspendedCompanies;
  final int pendingVerificationCompanies;
  final int trialsExpiringWithin7Days;
  final int totalPlatformUsers;
  final double totalRevenue;
  final double revenueThisMonth;

  /// Built from the plan catalogue rather than a fixed set — a super admin can
  /// add a plan at runtime, so this list is whatever exists today.
  final List<PlanCount> companiesByPlan;

  factory PlatformSummary.fromJson(Map<String, dynamic> json) =>
      PlatformSummary(
        totalCompanies: (json['totalCompanies'] as num?)?.toInt() ?? 0,
        activeCompanies: (json['activeCompanies'] as num?)?.toInt() ?? 0,
        trialCompanies: (json['trialCompanies'] as num?)?.toInt() ?? 0,
        suspendedCompanies: (json['suspendedCompanies'] as num?)?.toInt() ?? 0,
        pendingVerificationCompanies:
            (json['pendingVerificationCompanies'] as num?)?.toInt() ?? 0,
        trialsExpiringWithin7Days:
            (json['trialsExpiringWithin7Days'] as num?)?.toInt() ?? 0,
        totalPlatformUsers:
            (json['totalPlatformUsers'] as num?)?.toInt() ?? 0,
        totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0,
        revenueThisMonth: (json['revenueThisMonth'] as num?)?.toDouble() ?? 0,
        companiesByPlan:
            (json['companiesByPlan'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(PlanCount.fromJson)
                .toList(growable: false),
      );
}

class PlanCount {
  const PlanCount({required this.code, required this.name, required this.count});

  final String code;
  final String name;
  final int count;

  factory PlanCount.fromJson(Map<String, dynamic> json) => PlanCount(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// One day of the platform's trend lines, taken from a nightly snapshot. Days
/// before snapshots were being taken are simply missing rather than zero.
class PlatformMetricsPoint {
  const PlatformMetricsPoint({
    required this.date,
    required this.totalCompanies,
    required this.activeCompanies,
    required this.trialCompanies,
    required this.suspendedCompanies,
    required this.revenue,
  });

  final String date;
  final int totalCompanies;
  final int activeCompanies;
  final int trialCompanies;
  final int suspendedCompanies;
  final double revenue;

  factory PlatformMetricsPoint.fromJson(Map<String, dynamic> json) =>
      PlatformMetricsPoint(
        date: json['date'] as String? ?? '',
        totalCompanies: (json['totalCompanies'] as num?)?.toInt() ?? 0,
        activeCompanies: (json['activeCompanies'] as num?)?.toInt() ?? 0,
        trialCompanies: (json['trialCompanies'] as num?)?.toInt() ?? 0,
        suspendedCompanies:
            (json['suspendedCompanies'] as num?)?.toInt() ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      );
}
