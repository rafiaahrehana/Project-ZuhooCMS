import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';

export interface InvoiceDetailDto {
  invoiceNumber: string;
  clientName: string | null;
  amount: number;
  daysOverdue: number;
}

export interface AnnouncementDto {
  title: string;
  content: string;
  timeAgo: string;
}

export interface DashboardSummary {
  totalLeads: number;
  newLeads: number;
  qualifiedLeads: number;
  totalClients: number;
  openOpportunities: number;
  pipelineValue: number;
  weightedForecast: number;
  pendingRequests: number;
  inProgressRequests: number;
  completedRequestsAllTime: number;
  slaBreachedOpen: number;
  totalServiceRequests: number;
  openTickets: number;
  newTickets: number;
  outstandingInvoiceAmount: number;
  walletBalance: number;
  walletCreditBalance: number;
  totalEmployees: number;
  pendingLeaveApprovals: number;
  payrollProcessedThisMonth: number;

  // Trends: percent vs the previous window, or null when there is nothing to compare.
  leadsTrend: number | null;
  clientsTrend: number | null;
  opportunitiesTrend: number | null;
  weightedForecastTrend: number | null;
  
  salesOverviewLabels: string[];
  salesOverviewData: number[];
  salesOverviewTrend: number | null;
  
  serviceDeskPendingCount: number;
  serviceDeskInProgressCount: number;
  serviceDeskResolvedCount: number;
  /** Requests in WAITING_CLIENT (same value as serviceDeskWaitingOnClientCount). */
  serviceDeskOnHoldCount: number;
  serviceDeskWaitingOnClientCount?: number;
  
  tasksCreatedCount: number;
  tasksCreatedTrend: number | null;
  tasksCompletedCount: number;
  tasksCompletedTrend: number | null;
  tasksOverdueCount: number;
  tasksOverdueTrend: number | null;
  
  overdueInvoices: InvoiceDetailDto[];
  
  walletBalanceTrend: number | null;
  walletCredits: number;
  walletDebits: number;
  
  employeesPresentToday: number;
  employeesOnLeave: number;
  employeesTrend: number | null;
  
  announcements: AnnouncementDto[];

  /**
   * Blocks the backend could NOT read this time: "crm", "servicedesk", "support", "finance", "hrm", "payroll".
   * Every figure a failed block feeds is zero in this response, so without this a down service looks exactly
   * like a company with no data. Optional: a backend that does not send it leaves the notice hidden.
   * A block the viewer lacks permission for is never listed - it was never asked for.
   */
  unavailableSections?: string[];
}

// Mirrors backend PlanCompanyCount
export interface PlanCompanyCount {
  code: string;
  name: string;
  count: number;
}

// Mirrors backend PlatformSummaryResponse (GET /api/dashboard/platform-summary)
export interface PlatformSummary {
  totalCompanies: number;
  activeCompanies: number;
  trialCompanies: number;
  suspendedCompanies: number;
  pendingVerificationCompanies: number;
  trialsExpiringWithin7Days: number;
  companiesByPlan: PlanCompanyCount[];
  totalPlatformUsers: number;
  totalRevenue: number;
  revenueThisMonth: number;
}

// Mirrors backend PlatformMetricsPoint (GET /api/dashboard/platform-metrics-history)
export interface PlatformMetricsPoint {
  date: string;
  totalCompanies: number;
  activeCompanies: number;
  trialCompanies: number;
  suspendedCompanies: number;
  revenue: number;
}

// Mirrors backend ClientSummaryResponse (GET /api/dashboard/client-summary)
export interface ClientSummary {
  pendingRequests: number;
  inProgressRequests: number;
  completedRequests: number;
  unpaidInvoices: number;
  outstandingInvoiceAmount: number;
  /** As on DashboardSummary: "servicedesk" and/or "finance" when the zero shown is a guess, not a fact. */
  unavailableSections?: string[];
}

// Mirrors backend RecommendationResponse
export interface RecommendationResponse {
  type: string;
  severity: string;
  message: string;
  link: string;
}

// Mirrors backend InsightsResponse
export interface InsightsResponse {
  insights: string;
  generatedInMs: number;
}

@Injectable({ providedIn: 'root' })
export class DashboardService {
  constructor(private api: ApiService) {}

  getSummary(from?: string, to?: string): Observable<DashboardSummary> {
    return this.api.get<DashboardSummary>('/dashboard/summary', { from, to });
  }

  getPlatformSummary(): Observable<PlatformSummary> {
    return this.api.get<PlatformSummary>('/dashboard/platform-summary');
  }

  getPlatformMetricsHistory(days: number): Observable<PlatformMetricsPoint[]> {
    return this.api.get<PlatformMetricsPoint[]>('/dashboard/platform-metrics-history', { days });
  }

  getClientSummary(): Observable<ClientSummary> {
    return this.api.get<ClientSummary>('/dashboard/client-summary');
  }

  getRecommendations(): Observable<RecommendationResponse[]> {
    return this.api.get<RecommendationResponse[]>('/dashboard/recommendations');
  }

  getInsights(): Observable<InsightsResponse> {
    return this.api.get<InsightsResponse>('/dashboard/insights');
  }
}
