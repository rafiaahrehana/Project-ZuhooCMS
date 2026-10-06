package com.zuhoocms.modules.dashboard;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.enums.InvoiceStatus;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.enums.LeaveRequestStatus;
import com.zuhoocms.enums.PayrollStatus;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.enums.TaskStatus;
import com.zuhoocms.enums.WalletTransactionType;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.BusinessInsightsPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.modules.crm.opportunity.OpportunityRepository;
import com.zuhoocms.modules.crm.opportunity.OpportunityStage;
import com.zuhoocms.modules.demo.DemoAccount;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.modules.hrm.announcement.AnnouncementResponse;
import com.zuhoocms.modules.hrm.announcement.AnnouncementService;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.modules.hrm.payroll.PayrollRepository;
import com.zuhoocms.modules.itam.software.SoftwareLicenseRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.support.ticket.SupportTicketRepository;
import com.zuhoocms.modules.support.ticket.TicketStatus;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.payment.wallet.Wallet;
import com.zuhoocms.shared.payment.wallet.WalletRepository;
import com.zuhoocms.shared.payment.wallet.WalletTransactionRepository;
import com.zuhoocms.shared.subscription.SubscriptionHistoryRepository;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinitionRepository;
import jakarta.persistence.EntityManager;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Supplier;

/**
 * Tenant, client and platform dashboards.
 *
 * <p>Every number is real: an empty company sees zeros, empty lists and null trends, never placeholders.
 * <p>Each widget is gated by the same VIEW permission its module uses, so an employee without INVOICE_VIEW sees no invoice numbers.
 * <p>Each widget runs in its own read-only transaction: one shared transaction meant a single failing query left it rollback-only and poisoned every later widget.
 * <p>A widget whose query fails still leaves the page up, but its section is named in {@code unavailableSections} so the client can say the zero it shows is a guess rather than a fact.
 */
@Slf4j
@Service
@Transactional(readOnly = true)
public class DashboardServiceImpl implements DashboardService {

    private final LeadRepository leadRepository;
    private final ClientRepository clientRepository;
    private final OpportunityRepository opportunityRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final SupportTicketRepository supportTicketRepository;
    private final ClientInvoiceRepository invoiceRepository;
    private final WalletRepository walletRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final SoftwareLicenseRepository softwareLicenseRepository;
    private final EmployeeRepository employeeRepository;
    private final LeaveRequestRepository leaveRequestRepository;
    private final PayrollRepository payrollRepository;
    private final CompanyRepository companyRepository;
    private final UserRepository userRepository;
    private final SubscriptionHistoryRepository subscriptionHistoryRepository;
    private final SubscriptionPlanDefinitionRepository subscriptionPlanDefinitionRepository;
    private final PlatformMetricsSnapshotRepository platformMetricsSnapshotRepository;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final AnnouncementService announcementService;
    private final DemoAccount demoAccount;
    private final EntityManager entityManager;
    private final TransactionTemplate widgetTx;

    /** Zone used for "today" and period boundaries; blank = the server's default zone. */
    @Value("${app.zone:}")
    private String zoneConfig;

    public DashboardServiceImpl(LeadRepository leadRepository, ClientRepository clientRepository,
                                OpportunityRepository opportunityRepository,
                                ServiceRequestRepository serviceRequestRepository,
                                SupportTicketRepository supportTicketRepository,
                                ClientInvoiceRepository invoiceRepository, WalletRepository walletRepository,
                                WalletTransactionRepository walletTransactionRepository,
                                SoftwareLicenseRepository softwareLicenseRepository,
                                EmployeeRepository employeeRepository, LeaveRequestRepository leaveRequestRepository,
                                PayrollRepository payrollRepository, CompanyRepository companyRepository,
                                UserRepository userRepository,
                                SubscriptionHistoryRepository subscriptionHistoryRepository,
                                SubscriptionPlanDefinitionRepository subscriptionPlanDefinitionRepository,
                                PlatformMetricsSnapshotRepository platformMetricsSnapshotRepository,
                                AiService aiService, AiTransactionBoundary aiTx, SecurityUtil securityUtil,
                                AuthorizationService authorizationService,
                                @Lazy AnnouncementService announcementService, DemoAccount demoAccount,
                                EntityManager entityManager, PlatformTransactionManager transactionManager) {
        this.leadRepository = leadRepository;
        this.clientRepository = clientRepository;
        this.opportunityRepository = opportunityRepository;
        this.serviceRequestRepository = serviceRequestRepository;
        this.supportTicketRepository = supportTicketRepository;
        this.invoiceRepository = invoiceRepository;
        this.walletRepository = walletRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.softwareLicenseRepository = softwareLicenseRepository;
        this.employeeRepository = employeeRepository;
        this.leaveRequestRepository = leaveRequestRepository;
        this.payrollRepository = payrollRepository;
        this.companyRepository = companyRepository;
        this.userRepository = userRepository;
        this.subscriptionHistoryRepository = subscriptionHistoryRepository;
        this.subscriptionPlanDefinitionRepository = subscriptionPlanDefinitionRepository;
        this.platformMetricsSnapshotRepository = platformMetricsSnapshotRepository;
        this.aiService = aiService;
        this.aiTx = aiTx;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.announcementService = announcementService;
        this.demoAccount = demoAccount;
        this.entityManager = entityManager;
        TransactionTemplate t = new TransactionTemplate(transactionManager);
        t.setReadOnly(true);
        t.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.widgetTx = t;
    }

    private ZoneId zone() {
        return zoneConfig == null || zoneConfig.isBlank() ? ZoneId.systemDefault() : ZoneId.of(zoneConfig.trim());
    }

    /*
     * Section tokens for the responses' unavailableSections. The web and mobile clients match on these exact
     * strings, so they are named once here.
     */
    private static final String CRM = "crm";
    private static final String SERVICEDESK = "servicedesk";
    private static final String SUPPORT = "support";
    private static final String FINANCE = "finance";
    private static final String HRM = "hrm";
    private static final String PAYROLL = "payroll";

    /**
     * One dashboard assembly: runs each widget in its own read-only transaction and remembers which sections could
     * not be read, so the response can say "unavailable" instead of quietly showing a zero the user will believe.
     *
     * <p>A section is named only when a query actually threw - the only way reading can fail here, since every
     * widget is a synchronous query against this application's own database (no remote call to time out). It is
     * NOT named when the widget answered with nothing: no rows, no wallet, no previous period to compare against
     * are all real answers. Nor when the viewer lacks the permission, because then nothing was asked in the first
     * place. That distinction is the whole point: the flag means "this zero is a guess".
     *
     * <p>One instance per request - it is mutable, and this service is a singleton.
     */
    private final class Widgets {

        private final Set<String> unavailable = new LinkedHashSet<>();

        /** Runs one widget; a failure is logged, marks {@code section} unavailable and yields {@code fallback}. */
        <T> T run(String section, String name, T fallback, Supplier<T> work) {
            try {
                T result = widgetTx.execute(status -> work.get());
                return result != null ? result : fallback;
            } catch (RuntimeException ex) {
                log.warn("Dashboard widget '{}' failed - reporting section '{}' as unavailable: {}",
                        name, section, ex.toString(), ex);
                unavailable.add(section);
                return fallback;
            }
        }

        /** The failed sections, in the order they failed; empty when everything answered. */
        List<String> unavailableSections() {
            return List.copyOf(unavailable);
        }
    }

    private boolean can(PermissionCode code) {
        return authorizationService.hasPermission(code);
    }

    /** Percent change, or null when there is no previous value to compare against. */
    private static Double trend(long current, long previous) {
        if (previous <= 0) return null;
        return ((double) (current - previous) / previous) * 100.0;
    }

    private long count(String jpql, Object... params) {
        var q = entityManager.createQuery(jpql, Long.class);
        for (int i = 0; i < params.length; i += 2) {
            q.setParameter((String) params[i], params[i + 1]);
        }
        Long v = q.getSingleResult();
        return v == null ? 0 : v;
    }

    @Override
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public DashboardSummaryResponse getSummary(LocalDate from, LocalDate to) {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }

        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        LocalDateTime now = LocalDateTime.now(zone);
        // Period is [from 00:00, day after `to` 00:00): end-exclusive, so the whole of `to` counts (a 23:59:59 end drops its last second).
        LocalDateTime periodStart = from != null ? from.atStartOfDay() : null;
        LocalDateTime periodEnd = to != null ? to.plusDays(1).atStartOfDay() : null;
        boolean hasPeriod = periodStart != null && periodEnd != null;

        boolean leadsOk = can(PermissionCode.LEAD_VIEW);
        boolean clientsOk = can(PermissionCode.CLIENT_VIEW);
        boolean oppsOk = can(PermissionCode.OPPORTUNITY_VIEW);
        boolean requestsOk = can(PermissionCode.SERVICE_REQUEST_VIEW);
        boolean ticketsOk = can(PermissionCode.TICKET_VIEW);
        boolean invoicesOk = can(PermissionCode.INVOICE_VIEW);
        boolean walletOk = can(PermissionCode.WALLET_VIEW);
        boolean employeesOk = can(PermissionCode.EMPLOYEE_VIEW);
        boolean attendanceOk = can(PermissionCode.ATTENDANCE_VIEW);
        boolean leaveOk = can(PermissionCode.LEAVE_VIEW);
        boolean payrollOk = can(PermissionCode.PAYROLL_VIEW);

        var b = DashboardSummaryResponse.builder();
        Widgets w = new Widgets();

        LocalDateTime weekAgo = now.minusDays(7);
        LocalDateTime twoWeeksAgo = now.minusDays(14);
        if (leadsOk) {
            b.totalLeads(w.run(CRM, "totalLeads", 0L, () -> leadRepository.countByCompanyId(companyId)));
            // "New in period" = created in the period, whatever its status is now.
            b.newLeads(w.run(CRM, "newLeads", 0L, () -> hasPeriod
                    ? count("SELECT COUNT(l) FROM Lead l WHERE l.company.id = :c AND l.createdAt >= :s AND l.createdAt < :e",
                            "c", companyId, "s", periodStart, "e", periodEnd)
                    : leadRepository.countByCompanyIdAndStatusAndConvertedFalse(companyId, LeadStatus.NEW)));
            b.qualifiedLeads(w.run(CRM, "qualifiedLeads", 0L,
                    () -> leadRepository.countByCompanyIdAndStatusAndConvertedFalse(companyId, LeadStatus.QUALIFIED)));
            b.leadsTrend(w.run(CRM, "leadsTrend", null, () -> trend(
                    count("SELECT COUNT(l) FROM Lead l WHERE l.company.id = :c AND l.createdAt >= :s", "c", companyId, "s", weekAgo),
                    count("SELECT COUNT(l) FROM Lead l WHERE l.company.id = :c AND l.createdAt >= :s AND l.createdAt < :e",
                            "c", companyId, "s", twoWeeksAgo, "e", weekAgo))));

            // Leads created per day over the last 7 days (real counts, zeros included).
            List<String> labels = new ArrayList<>();
            List<Long> data = new ArrayList<>();
            for (int i = 6; i >= 0; i--) {
                LocalDate d = today.minusDays(i);
                labels.add(d.getMonth().name().charAt(0) + d.getMonth().name().substring(1, 3).toLowerCase() + " " + d.getDayOfMonth());
                data.add(w.run(CRM, "salesOverview", 0L, () -> count(
                        "SELECT COUNT(l) FROM Lead l WHERE l.company.id = :c AND l.createdAt >= :s AND l.createdAt < :e",
                        "c", companyId, "s", d.atStartOfDay(), "e", d.plusDays(1).atStartOfDay())));
            }
            b.salesOverviewLabels(labels).salesOverviewData(data);
            long thisWeek = data.stream().mapToLong(Long::longValue).sum();
            b.salesOverviewTrend(w.run(CRM, "salesOverviewTrend", null, () -> trend(thisWeek, count(
                    "SELECT COUNT(l) FROM Lead l WHERE l.company.id = :c AND l.createdAt >= :s AND l.createdAt < :e",
                    "c", companyId, "s", today.minusDays(13).atStartOfDay(), "e", today.minusDays(6).atStartOfDay()))));
        } else {
            b.salesOverviewLabels(List.of()).salesOverviewData(List.of());
        }

        if (clientsOk) {
            b.totalClients(w.run(CRM, "totalClients", 0L, () -> clientRepository.countByCompanyId(companyId)));
            b.clientsTrend(w.run(CRM, "clientsTrend", null, () -> trend(
                    count("SELECT COUNT(c) FROM Client c WHERE c.company.id = :c AND c.createdAt >= :s", "c", companyId, "s", weekAgo),
                    count("SELECT COUNT(c) FROM Client c WHERE c.company.id = :c AND c.createdAt >= :s AND c.createdAt < :e",
                            "c", companyId, "s", twoWeeksAgo, "e", weekAgo))));
        }

        b.pipelineValue(BigDecimal.ZERO).weightedForecast(BigDecimal.ZERO);
        if (oppsOk) {
            record Pipeline(long open, BigDecimal value, BigDecimal weighted) {}
            Pipeline p = w.run(CRM, "pipeline", new Pipeline(0, BigDecimal.ZERO, BigDecimal.ZERO), () -> {
                long open = 0;
                BigDecimal value = BigDecimal.ZERO;
                BigDecimal weighted = BigDecimal.ZERO;
                for (var stage : opportunityRepository.summarizePipeline(companyId)) {
                    if (!stage.getStage().isClosed()) {
                        open += stage.getDealCount();
                        value = value.add(stage.getTotalAmount() != null ? stage.getTotalAmount() : BigDecimal.ZERO);
                        weighted = weighted.add(stage.getWeightedAmount() != null ? stage.getWeightedAmount() : BigDecimal.ZERO);
                    }
                }
                return new Pipeline(open, value, weighted);
            });
            b.openOpportunities(p.open()).pipelineValue(p.value()).weightedForecast(p.weighted());
            // No opportunity-history snapshot exists to compare against: null, not a guess.
            b.opportunitiesTrend(null).weightedForecastTrend(null);
        }

        if (requestsOk) {
            long pending = w.run(SERVICEDESK, "pendingRequests", 0L, () ->
                    serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.PENDING)
                    + serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.QUOTATION_PENDING)
                    + serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.RESUBMITTED));
            long inProgress = w.run(SERVICEDESK, "inProgressRequests", 0L, () ->
                    serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.IN_PROGRESS)
                    + serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.ASSIGNED)
                    + serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.UNDER_REVIEW));
            long completed = w.run(SERVICEDESK, "completedRequests", 0L, () ->
                    serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.COMPLETED));
            // "On hold" = WAITING_CLIENT only; CANCELLED/REJECTED are closed, not on hold.
            long waitingClient = w.run(SERVICEDESK, "waitingOnClient", 0L, () ->
                    serviceRequestRepository.countByCompanyIdAndStatus(companyId, ServiceRequestStatus.WAITING_CLIENT));
            b.pendingRequests(pending).inProgressRequests(inProgress).completedRequestsAllTime(completed)
                    .serviceDeskPendingCount(pending).serviceDeskInProgressCount(inProgress)
                    .serviceDeskResolvedCount(completed)
                    .serviceDeskOnHoldCount(waitingClient).serviceDeskWaitingOnClientCount(waitingClient);
            b.slaBreachedOpen(w.run(SERVICEDESK, "slaBreached", 0L, () -> serviceRequestRepository
                    .countByCompanyIdAndSlaBreachTrueAndStatusNotIn(companyId, List.of(
                            ServiceRequestStatus.COMPLETED, ServiceRequestStatus.CANCELLED, ServiceRequestStatus.REJECTED))));
            b.totalServiceRequests(w.run(SERVICEDESK, "totalRequests", 0L,
                    () -> serviceRequestRepository.countByCompanyId(companyId)));

            LocalDateTime curStart = hasPeriod ? periodStart : now.minusDays(7);
            LocalDateTime curEnd = hasPeriod ? periodEnd : now;
            long days = Math.max(1, ChronoUnit.DAYS.between(curStart.toLocalDate(), curEnd.toLocalDate()));
            LocalDateTime prevStart = curStart.minusDays(days);
            long created = w.run(SERVICEDESK, "tasksCreated", 0L, () -> count(
                    "SELECT COUNT(t) FROM Task t WHERE t.company.id = :c AND t.createdAt >= :s AND t.createdAt < :e",
                    "c", companyId, "s", curStart, "e", curEnd));
            long prevCreated = w.run(SERVICEDESK, "tasksCreatedPrev", 0L, () -> count(
                    "SELECT COUNT(t) FROM Task t WHERE t.company.id = :c AND t.createdAt >= :s AND t.createdAt < :e",
                    "c", companyId, "s", prevStart, "e", curStart));
            long done = w.run(SERVICEDESK, "tasksCompleted", 0L, () -> count(
                    "SELECT COUNT(t) FROM Task t WHERE t.company.id = :c AND t.status = :st AND t.completedAt >= :s AND t.completedAt < :e",
                    "c", companyId, "st", TaskStatus.COMPLETED, "s", curStart, "e", curEnd));
            long prevDone = w.run(SERVICEDESK, "tasksCompletedPrev", 0L, () -> count(
                    "SELECT COUNT(t) FROM Task t WHERE t.company.id = :c AND t.status = :st AND t.completedAt >= :s AND t.completedAt < :e",
                    "c", companyId, "st", TaskStatus.COMPLETED, "s", prevStart, "e", curStart));
            b.tasksCreatedCount(created).tasksCreatedTrend(trend(created, prevCreated))
                    .tasksCompletedCount(done).tasksCompletedTrend(trend(done, prevDone))
                    .tasksOverdueCount(w.run(SERVICEDESK, "tasksOverdue", 0L, () -> count(
                            "SELECT COUNT(t) FROM Task t WHERE t.company.id = :c AND t.status <> :st AND t.dueDate < :d",
                            "c", companyId, "st", TaskStatus.COMPLETED, "d", today)))
                    .tasksOverdueTrend(null);
        }

        if (ticketsOk) {
            b.openTickets(w.run(SUPPORT, "openTickets", 0L, () ->
                    supportTicketRepository.countByStatusAndCompanyId(TicketStatus.OPEN, companyId)
                    + supportTicketRepository.countByStatusAndCompanyId(TicketStatus.IN_PROGRESS, companyId)
                    + supportTicketRepository.countByStatusAndCompanyId(TicketStatus.WAITING, companyId)));
            b.newTickets(w.run(SUPPORT, "newTickets", 0L, () -> hasPeriod
                    ? count("SELECT COUNT(t) FROM SupportTicket t WHERE t.companyId = :c AND t.createdAt >= :s AND t.createdAt < :e",
                            "c", companyId, "s", periodStart, "e", periodEnd)
                    : supportTicketRepository.countByStatusAndCompanyId(TicketStatus.NEW, companyId)));
        }

        b.outstandingInvoiceAmount(BigDecimal.ZERO).overdueInvoices(List.of());
        if (invoicesOk) {
            b.outstandingInvoiceAmount(w.run(FINANCE, "outstanding", BigDecimal.ZERO, () -> invoiceRepository
                    .sumOutstandingByCompanyId(companyId,
                            List.of(InvoiceStatus.ISSUED, InvoiceStatus.PARTIALLY_PAID, InvoiceStatus.OVERDUE))
                    .orElse(BigDecimal.ZERO)));
            b.overdueInvoices(w.run(FINANCE, "overdueInvoices", List.<InvoiceDetailDto>of(), () -> {
                List<InvoiceDetailDto> out = new ArrayList<>();
                for (ClientInvoice inv : entityManager.createQuery(
                                "SELECT i FROM ClientInvoice i LEFT JOIN FETCH i.client WHERE i.companyId = :c AND i.dueDate < :d "
                                        + "AND i.status NOT IN :excluded ORDER BY i.dueDate ASC, i.id ASC", ClientInvoice.class)
                        .setParameter("c", companyId)
                        .setParameter("d", today)
                        .setParameter("excluded", List.of(InvoiceStatus.PAID, InvoiceStatus.CANCELLED, InvoiceStatus.DRAFT))
                        .setMaxResults(5)
                        .getResultList()) {
                    out.add(InvoiceDetailDto.builder()
                            .invoiceNumber(inv.getInvoiceNumber())
                            .clientName(inv.getClient() != null ? inv.getClient().getClientCompanyName() : null)
                            .amount(inv.getTotalAmount())
                            .daysOverdue(ChronoUnit.DAYS.between(inv.getDueDate(), today))
                            .build());
                }
                return out;
            }));
        }

        b.walletBalance(BigDecimal.ZERO).walletCreditBalance(BigDecimal.ZERO)
                .walletCredits(BigDecimal.ZERO).walletDebits(BigDecimal.ZERO);
        if (walletOk) {
            // A company with no wallet row is a real answer (null), not a failure - only run() records failures.
            Wallet wallet = w.run(FINANCE, "wallet", null, () ->
                    walletRepository.findByContextTypeAndContextId("COMPANY", companyId).orElse(null));
            if (wallet != null) {
                LocalDateTime monthStart = today.withDayOfMonth(1).atStartOfDay();
                BigDecimal credits = w.run(FINANCE, "walletCredits", BigDecimal.ZERO, () ->
                        sumWallet(companyId, monthStart, WalletTransactionType.CREDIT, WalletTransactionType.REFUND_CREDIT,
                                WalletTransactionType.REFERRAL_REWARD));
                BigDecimal debits = w.run(FINANCE, "walletDebits", BigDecimal.ZERO, () ->
                        sumWallet(companyId, monthStart, WalletTransactionType.DEBIT, WalletTransactionType.CREDIT_APPLIED));
                b.walletBalance(wallet.getBalance() != null ? wallet.getBalance() : BigDecimal.ZERO)
                        .walletCreditBalance(wallet.getCreditBalance() != null ? wallet.getCreditBalance() : BigDecimal.ZERO)
                        .walletCredits(credits).walletDebits(debits)
                        // Net change this month (credits - debits), not a constant.
                        .walletBalanceTrend(credits.subtract(debits).doubleValue());
            }
        }

        if (employeesOk || attendanceOk) {
            long headcount = w.run(HRM, "totalEmployees", 0L, () -> {
                Company company = companyRepository.findById(companyId).orElse(null);
                Long ownerUserId = company != null && company.getOwner() != null ? company.getOwner().getId() : null;
                // Active employees only (resigned/terminated rows no longer inflate headcount).
                return ownerUserId != null
                        ? employeeRepository.countByCompanyIdAndActiveTrueAndUserIdNot(companyId, ownerUserId)
                        : employeeRepository.countByCompanyIdAndActiveTrue(companyId);
            });
            b.totalEmployees(headcount);
            b.employeesTrend(null);
        }
        if (attendanceOk) {
            // Present today = attendance actually marked today; approved leave covering today.
            b.employeesPresentToday(w.run(HRM, "presentToday", 0L, () -> count(
                    "SELECT COUNT(DISTINCT a.employee.id) FROM Attendance a WHERE a.companyId = :c AND a.attendanceDate = :d "
                            + "AND a.status IN :present",
                    "c", companyId, "d", today, "present", List.of(AttendanceStatus.PRESENT, AttendanceStatus.LATE,
                            AttendanceStatus.WORK_FROM_HOME, AttendanceStatus.HALF_DAY, AttendanceStatus.PARTIAL_DAY))));
            b.employeesOnLeave(w.run(HRM, "onLeave", 0L, () -> count(
                    "SELECT COUNT(lr) FROM LeaveRequest lr WHERE lr.company.id = :c AND lr.status = :st "
                            + "AND :d BETWEEN lr.startDate AND lr.endDate",
                    "c", companyId, "st", LeaveRequestStatus.APPROVED, "d", today)));
        }
        if (leaveOk) {
            b.pendingLeaveApprovals(w.run(HRM, "pendingLeave", 0L,
                    () -> leaveRequestRepository.countByCompanyIdAndStatus(companyId, LeaveRequestStatus.PENDING)));
        }
        if (payrollOk) {
            b.payrollProcessedThisMonth(w.run(PAYROLL, "payroll", 0L, () -> payrollRepository
                    .countByCompanyIdAndPayMonthAndPayYearAndStatusIn(companyId, today.getMonthValue(), today.getYear(),
                            List.of(PayrollStatus.APPROVED, PayrollStatus.PAID))));
        }

        // Viewer's own notice-board feed, top 3; see AnnouncementServiceImpl.listActive for the audience/department rules.
        b.announcements(w.run(HRM, "announcements", List.<AnnouncementDto>of(), () -> {
            List<AnnouncementDto> out = new ArrayList<>();
            for (AnnouncementResponse a : announcementService.listActive()) {
                if (out.size() == 3) break;
                out.add(new AnnouncementDto(a.getTitle(), a.getBody(), timeAgo(a.getPublishedAt(), now)));
            }
            return out;
        }));

        // Last, so it names every section whose query failed above.
        b.unavailableSections(w.unavailableSections());

        return b.build();
    }

    private BigDecimal sumWallet(Long companyId, LocalDateTime from, WalletTransactionType... types) {
        BigDecimal total = BigDecimal.ZERO;
        for (WalletTransactionType type : types) {
            total = total.add(walletTransactionRepository
                    .sumByWalletContextTypeAndWalletContextIdAndTypeAfter("COMPANY", companyId, type, from)
                    .orElse(BigDecimal.ZERO));
        }
        return total;
    }

    private static String timeAgo(LocalDateTime at, LocalDateTime now) {
        if (at == null) return "";
        long mins = Math.max(0, ChronoUnit.MINUTES.between(at, now));
        if (mins < 60) return mins + "m ago";
        if (mins < 1440) return (mins / 60) + "h ago";
        return (mins / 1440) + "d ago";
    }

    @Override
    public List<RecommendationResponse> getRecommendations() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }
        List<RecommendationResponse> recommendations = new ArrayList<>();

        // Each rule is gated by the permission of the data it talks about.
        if (can(PermissionCode.OPPORTUNITY_VIEW)) {
            List<OpportunityStage> closedStages = List.of(OpportunityStage.WON, OpportunityStage.LOST);
            var staleDeals = opportunityRepository.findStaleOpenOpportunities(
                    companyId, closedStages, LocalDateTime.now().minusDays(14), PageRequest.of(0, 5));
            for (var deal : staleDeals) {
                recommendations.add(new RecommendationResponse(
                        "FOLLOW_UP", "WARNING",
                        "Opportunity \"" + deal.getName() + "\" has had no activity for over 14 days — follow up with "
                                + (deal.getClient() != null ? deal.getClient().getClientCompanyName() : "the client"),
                        "/crm/pipeline"));
            }
        }

        if (can(PermissionCode.SERVICE_REQUEST_VIEW)) {
            long slaBreached = serviceRequestRepository.countByCompanyIdAndSlaBreachTrueAndStatusNotIn(
                    companyId, List.of(ServiceRequestStatus.COMPLETED,
                            ServiceRequestStatus.CANCELLED,
                            ServiceRequestStatus.REJECTED));
            if (slaBreached > 0) {
                recommendations.add(new RecommendationResponse(
                        "SLA_RISK", "CRITICAL",
                        slaBreached + " open service request(s) have breached their SLA — reassign or escalate now",
                        "/servicedesk/requests"));
            }
        }

        if (can(PermissionCode.SOFTWARE_LICENSE_VIEW)) {
            var expiring = softwareLicenseRepository.findExpiringBetweenDates(
                    companyId, LocalDate.now(zone()), LocalDate.now(zone()).plusDays(30));
            for (var license : expiring) {
                recommendations.add(new RecommendationResponse(
                        "LICENSE_EXPIRY", "WARNING",
                        license.getSoftwareName() + " license expires on " + license.getLicenseExpiryDate()
                                + " — renew or cancel auto-billing",
                        "/itam/software"));
            }
        }

        if (can(PermissionCode.INVOICE_VIEW)) {
            long overdue = invoiceRepository.countByCompanyIdAndStatus(companyId, InvoiceStatus.OVERDUE);
            if (overdue > 0) {
                recommendations.add(new RecommendationResponse(
                        "OVERDUE_INVOICE", "CRITICAL",
                        overdue + " invoice(s) are overdue — send payment reminders to clients",
                        "/finance/invoices"));
            }
        }

        return recommendations;
    }

    // NOT_SUPPORTED overrides this class's @Transactional so the provider call isn't inside a transaction - see AiTransactionBoundary.
    @Override
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public InsightsResponse getAiInsights() {
        // The prompt summarises CRM and finance figures, so an employee who cannot see those modules must not get them back as an AI paragraph.
        for (PermissionCode code : List.of(PermissionCode.LEAD_VIEW, PermissionCode.CLIENT_VIEW,
                PermissionCode.OPPORTUNITY_VIEW, PermissionCode.INVOICE_VIEW, PermissionCode.WALLET_VIEW)) {
            if (!can(code)) {
                throw new ForbiddenException("AI insights need access to CRM and finance data (" + code + ")");
            }
        }
        DashboardSummaryResponse summary = getSummary(null, null);

        String metrics = """
                Total leads: %d (new: %d, qualified: %d)
                Accounts: %d
                Open opportunities: %d worth %s (weighted forecast: %s)
                Service requests — pending: %d, in progress: %d, SLA breached (open): %d
                Support tickets — open: %d, new: %d
                Outstanding invoice amount: %s
                Wallet balance: %s (credits: %s)
                """.formatted(
                summary.getTotalLeads(), summary.getNewLeads(), summary.getQualifiedLeads(),
                summary.getTotalClients(),
                summary.getOpenOpportunities(), summary.getPipelineValue(), summary.getWeightedForecast(),
                summary.getPendingRequests(), summary.getInProgressRequests(), summary.getSlaBreachedOpen(),
                summary.getOpenTickets(), summary.getNewTickets(),
                summary.getOutstandingInvoiceAmount(),
                summary.getWalletBalance(), summary.getWalletCreditBalance());

        String prompt = BusinessInsightsPromptBuilder.builder()
                .setMetrics(metrics)
                .build();

        long start = System.currentTimeMillis();
        String insights = aiService.generateRaw(AiFeature.BUSINESS_INSIGHTS, prompt);

        InsightsResponse response = new InsightsResponse();
        response.setInsights(insights);
        response.setGeneratedInMs(System.currentTimeMillis() - start);
        return response;
    }

    /** Demo owner id for the tenant-count queries (-1 when there is no demo). */
    private Long demoOwnerId() {
        Long id = demoAccount.demoUserId();
        return id != null ? id : -1L;
    }

    @Override
    public PlatformSummaryResponse getPlatformSummary() {
        LocalDate today = LocalDate.now(zone());
        Long demo = demoOwnerId();

        List<Role> platformRoles = List.of(
                Role.SUPER_ADMIN, Role.SYSTEM_ADMIN, Role.SUPPORT_AGENT, Role.SUPPORT_MANAGER,
                Role.MARKETING_MANAGER, Role.PLATFORM_ACCOUNTANT, Role.SALES_MANAGER);

        // Real tenants only: the platform tenant, the demo and never-verified sign-ups would inflate these numbers.
        List<PlanCompanyCount> companiesByPlan = subscriptionPlanDefinitionRepository.findAllByOrderByPriceAsc()
                .stream()
                .map(plan -> new PlanCompanyCount(plan.getCode(), plan.getName(),
                        companyRepository.countTenants(null, plan.getCode(), demo)))
                .toList();

        return PlatformSummaryResponse.builder()
                .totalCompanies(companyRepository.countTenants(null, null, demo))
                .activeCompanies(companyRepository.countTenants(CompanyStatus.ACTIVE, null, demo))
                .trialCompanies(companyRepository.countTenants(CompanyStatus.TRIAL, null, demo))
                .suspendedCompanies(companyRepository.countTenants(CompanyStatus.SUSPENDED, null, demo))
                .pendingVerificationCompanies(companyRepository.countTenants(CompanyStatus.PENDING_VERIFICATION, null, demo))
                .trialsExpiringWithin7Days(companyRepository.countTenantTrialsEndingBetween(today, today.plusDays(7), demo))
                .companiesByPlan(companiesByPlan)
                .totalPlatformUsers(userRepository.countByRoleIn(platformRoles))
                .totalRevenue(subscriptionHistoryRepository.sumTotalRevenue())
                .revenueThisMonth(subscriptionHistoryRepository.sumRevenueSince(
                        today.withDayOfMonth(1).atStartOfDay()))
                .build();
    }

    @Override
    public List<PlatformMetricsPoint> getPlatformMetricsHistory(int days) {
        LocalDate today = LocalDate.now(zone());
        LocalDate from = today.minusDays(days - 1L);

        // Company-count snapshots are one row per day from PlatformMetricsScheduler, so history is sparse on a fresh install.
        java.util.Map<LocalDate, PlatformMetricsSnapshot> snapshotsByDate = new java.util.LinkedHashMap<>();
        for (PlatformMetricsSnapshot s : platformMetricsSnapshotRepository
                .findBySnapshotDateGreaterThanEqualOrderBySnapshotDateAsc(from)) {
            snapshotsByDate.put(s.getSnapshotDate(), s);
        }

        // Revenue: bucketed in Java from the real SubscriptionHistory ledger.
        java.util.Map<LocalDate, BigDecimal> revenueByDate = new java.util.HashMap<>();
        for (var h : subscriptionHistoryRepository
                .findByChangedAtGreaterThanEqualOrderByChangedAtAsc(from.atStartOfDay())) {
            LocalDate day = h.getChangedAt().toLocalDate();
            BigDecimal paid = h.getAmountPaid() != null ? h.getAmountPaid() : BigDecimal.ZERO;
            revenueByDate.merge(day, paid, BigDecimal::add);
        }

        List<PlatformMetricsPoint> points = new ArrayList<>();
        for (LocalDate d = from; !d.isAfter(today); d = d.plusDays(1)) {
            PlatformMetricsSnapshot s = snapshotsByDate.get(d);
            points.add(new PlatformMetricsPoint(
                    d,
                    s != null ? s.getTotalCompanies() : 0,
                    s != null ? s.getActiveCompanies() : 0,
                    s != null ? s.getTrialCompanies() : 0,
                    s != null ? s.getSuspendedCompanies() : 0,
                    revenueByDate.getOrDefault(d, BigDecimal.ZERO)));
        }
        return points;
    }

    @Override
    @Transactional
    public void recordTodaysPlatformSnapshot() {
        LocalDate today = LocalDate.now(zone());
        Long demo = demoOwnerId();
        PlatformMetricsSnapshot snapshot = platformMetricsSnapshotRepository.findBySnapshotDate(today)
                .orElseGet(() -> PlatformMetricsSnapshot.builder().snapshotDate(today).build());

        // Same "real tenants only" rule as getPlatformSummary().
        snapshot.setTotalCompanies(companyRepository.countTenants(null, null, demo));
        snapshot.setActiveCompanies(companyRepository.countTenants(CompanyStatus.ACTIVE, null, demo));
        snapshot.setTrialCompanies(companyRepository.countTenants(CompanyStatus.TRIAL, null, demo));
        snapshot.setSuspendedCompanies(companyRepository.countTenants(CompanyStatus.SUSPENDED, null, demo));
        snapshot.setPendingVerificationCompanies(companyRepository.countTenants(CompanyStatus.PENDING_VERIFICATION, null, demo));

        platformMetricsSnapshotRepository.save(snapshot);
    }

    @Override
    public ClientSummaryResponse getClientSummary() {
        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();
        if (user == null || companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }

        Client client = clientRepository.findByUserId(user.getId())
                .orElseThrow(() -> new BadRequestException("No client record found for current user"));
        Long clientId = client.getId();

        // Requests and invoices are read independently, so one broken query costs the client its own half of the
        // page (reported in unavailableSections) instead of the whole page.
        Widgets w = new Widgets();

        long pending = w.run(SERVICEDESK, "clientPendingRequests", 0L,
                () -> serviceRequestRepository.countByCompanyIdAndClientIdAndStatus(
                        companyId, clientId, ServiceRequestStatus.PENDING)
                        + serviceRequestRepository.countByCompanyIdAndClientIdAndStatus(
                                companyId, clientId, ServiceRequestStatus.QUOTATION_PENDING));
        long inProgress = w.run(SERVICEDESK, "clientInProgressRequests", 0L,
                () -> serviceRequestRepository.countByCompanyIdAndClientIdAndStatus(
                        companyId, clientId, ServiceRequestStatus.IN_PROGRESS)
                        + serviceRequestRepository.countByCompanyIdAndClientIdAndStatus(
                                companyId, clientId, ServiceRequestStatus.ASSIGNED));
        long completed = w.run(SERVICEDESK, "clientCompletedRequests", 0L,
                () -> serviceRequestRepository.countByCompanyIdAndClientIdAndStatus(
                        companyId, clientId, ServiceRequestStatus.COMPLETED));

        List<InvoiceStatus> unpaidStatuses = List.of(InvoiceStatus.ISSUED, InvoiceStatus.PARTIALLY_PAID,
                InvoiceStatus.OVERDUE);

        long unpaidInvoices = w.run(FINANCE, "clientUnpaidInvoices", 0L,
                () -> invoiceRepository.countByCompanyIdAndClientIdAndStatusIn(companyId, clientId, unpaidStatuses));
        BigDecimal outstanding = w.run(FINANCE, "clientOutstanding", BigDecimal.ZERO,
                () -> invoiceRepository.sumOutstandingByCompanyIdAndClientId(companyId, clientId, unpaidStatuses)
                        .orElse(BigDecimal.ZERO));

        return ClientSummaryResponse.builder()
                .pendingRequests(pending)
                .inProgressRequests(inProgress)
                .completedRequests(completed)
                .unpaidInvoices(unpaidInvoices)
                .outstandingInvoiceAmount(outstanding)
                .unavailableSections(w.unavailableSections())
                .build();
    }
}
