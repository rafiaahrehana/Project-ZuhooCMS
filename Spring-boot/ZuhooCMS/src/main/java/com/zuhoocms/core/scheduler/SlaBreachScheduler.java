package com.zuhoocms.core.scheduler;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.support.ticket.SupportTicket;
import com.zuhoocms.modules.support.ticket.SupportTicketRepository;
import com.zuhoocms.modules.support.ticket.TicketStatus;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Pageable;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Flags SLA breaches and notifies whoever should act; each branch runs in its own transaction so one failure never rolls back another.
 * Rows are selected and marked in the same transaction; the ticket branches lock with SKIP LOCKED so overlapping runs can't notify the same ticket twice.
 */
@Slf4j
@Component
public class SlaBreachScheduler {

    private final ServiceRequestRepository serviceRequestRepository;
    private final SupportTicketRepository supportTicketRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private final TransactionTemplate transactionTemplate;

    /** Gates the support-ticket branches only, so a local run can start the app without these jobs touching existing rows. */
    @Value("${app.support.schedulers.enabled:true}")
    private boolean supportSchedulersEnabled;

    public SlaBreachScheduler(ServiceRequestRepository serviceRequestRepository,
                              SupportTicketRepository supportTicketRepository,
                              UserRepository userRepository,
                              NotificationService notificationService,
                              PlatformTransactionManager transactionManager) {
        this.serviceRequestRepository = serviceRequestRepository;
        this.supportTicketRepository = supportTicketRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    private static final List<ServiceRequestStatus> CLOSED_STATUSES = List.of(
            ServiceRequestStatus.COMPLETED,
            ServiceRequestStatus.CANCELLED,
            ServiceRequestStatus.REJECTED
    );

    // Only RESOLVED/CLOSED are terminal - REOPENED and everything before RESOLVED can still be past its deadline.
    private static final List<TicketStatus> CLOSED_TICKET_STATUSES = List.of(
            TicketStatus.RESOLVED,
            TicketStatus.CLOSED
    );

    /** What to tell whom about one breached ticket, captured inside the marking transaction. */
    private record TicketBreach(Long ticketId, String ticketNumber, String title, Long companyId,
                                Long assignedAgentUserId, String kind) {
    }

    @Scheduled(cron = "0 */30 * * * *")
    public void markSlaBreaches() {
        LocalDateTime now = LocalDateTime.now();

        runBranch("service requests", () -> markServiceRequestBreaches(now));

        if (supportSchedulersEnabled) {
            runBranch("ticket resolution SLA", () -> notifyTicketBreaches(markTicketResolutionBreaches(now)));
            runBranch("ticket first-response SLA", () -> notifyTicketBreaches(markTicketFirstResponseBreaches(now)));
        }
    }

    private void runBranch(String name, Runnable branch) {
        try {
            branch.run();
        } catch (RuntimeException ex) {
            log.error("SLA breach sweep for {} failed: {}", name, ex.getMessage(), ex);
        }
    }

    private void markServiceRequestBreaches(LocalDateTime now) {
        transactionTemplate.executeWithoutResult(status -> {
            List<ServiceRequest> newlyBreached =
                    serviceRequestRepository.findNewlyBreached(now, CLOSED_STATUSES);

            // markSlaBreached() also keeps the breach history (firstBreachedAt/breachCount).
            for (ServiceRequest request : newlyBreached) {
                request.markSlaBreached(now);
            }

            for (ServiceRequest request : newlyBreached) {
                if (request.getAssignedEmployee() == null
                        || request.getAssignedEmployee().getUser() == null) {
                    continue;
                }
                try {
                    notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                            NotificationType.SLA_BREACHED,
                            "SLA breached",
                            "Service request \"" + request.getTitle() + "\" has passed its SLA deadline",
                            request.getAssignedEmployee().getUser().getId(),
                            request.getCompany().getId(),
                            request.getId()
                    ));
                } catch (RuntimeException ex) {
                    log.warn("SLA notification failed for service request {}: {}", request.getId(), ex.getMessage());
                }
            }
        });
    }

    /** Locks, marks and returns the tickets whose resolution deadline just passed. */
    private List<TicketBreach> markTicketResolutionBreaches(LocalDateTime now) {
        List<TicketBreach> breaches = transactionTemplate.execute(status -> {
            List<TicketBreach> result = new ArrayList<>();
            for (SupportTicket ticket : supportTicketRepository.lockNewlyResolutionBreached(now, CLOSED_TICKET_STATUSES)) {
                ticket.setSlaBreached(true);
                ticket.setSlaBreachReason("Resolution deadline passed at " + ticket.getResolutionDeadline().withNano(0));
                result.add(toBreach(ticket, "resolution"));
            }
            return result;
        });
        return breaches != null ? breaches : List.of();
    }

    /** Locks, marks and returns the tickets that got no first response before its deadline. */
    private List<TicketBreach> markTicketFirstResponseBreaches(LocalDateTime now) {
        List<TicketBreach> breaches = transactionTemplate.execute(status -> {
            List<TicketBreach> result = new ArrayList<>();
            for (SupportTicket ticket : supportTicketRepository.lockNewlyFirstResponseBreached(now, CLOSED_TICKET_STATUSES)) {
                ticket.setFirstResponseBreached(true);
                if (!ticket.isSlaBreached()) {
                    ticket.setSlaBreachReason("First response deadline passed at " + ticket.getFirstResponseDeadline().withNano(0));
                }
                result.add(toBreach(ticket, "first-response"));
            }
            return result;
        });
        return breaches != null ? breaches : List.of();
    }

    private static TicketBreach toBreach(SupportTicket ticket, String kind) {
        Long agentUserId = ticket.getAssignedToAgent() != null && ticket.getAssignedToAgent().getUser() != null
                ? ticket.getAssignedToAgent().getUser().getId() : null;
        return new TicketBreach(ticket.getId(), ticket.getTicketNumber(), ticket.getTitle(),
                ticket.getCompanyId(), agentUserId, kind);
    }

    /** Assigned tickets page their agent; unassigned ones page every SUPPORT_MANAGER, which used to alert no one. */
    private void notifyTicketBreaches(List<TicketBreach> breaches) {
        if (breaches.isEmpty()) return;
        List<Long> managerIds = null;
        for (TicketBreach breach : breaches) {
            List<Long> recipients;
            if (breach.assignedAgentUserId() != null) {
                recipients = List.of(breach.assignedAgentUserId());
            } else {
                if (managerIds == null) {
                    managerIds = userRepository.findByRoleIn(List.of(Role.SUPPORT_MANAGER), Pageable.unpaged())
                            .map(User::getId).getContent();
                }
                recipients = managerIds;
            }
            String message = "Ticket \"" + breach.title() + "\" (" + breach.ticketNumber() + ") has passed its "
                    + breach.kind() + " SLA deadline"
                    + (breach.assignedAgentUserId() == null ? " and is still unassigned" : "");
            for (Long recipientId : recipients) {
                try {
                    notificationService.send(CreateNotificationRequest.of(
                            NotificationType.SLA_BREACHED,
                            "SLA breached",
                            message,
                            "/support/tickets/" + breach.ticketId(),
                            recipientId,
                            breach.companyId()
                    ));
                } catch (RuntimeException ex) {
                    log.warn("SLA notification failed for ticket {} to user {}: {}",
                            breach.ticketId(), recipientId, ex.getMessage());
                }
            }
        }
    }
}
