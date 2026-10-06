package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.crm.activity.CrmActivity;
import com.zuhoocms.modules.crm.activity.CrmActivityRepository;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.modules.crm.opportunity.Opportunity;
import com.zuhoocms.modules.crm.opportunity.OpportunityRepository;
import com.zuhoocms.modules.crm.opportunity.OpportunityStage;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Notifies on due follow-ups only; followUpDone stays manual (see CrmActivityService.markCompleted).
 * Queries are cross-company and paged, filtering on the column the loop stamps (followUpNotifiedAt / staleNotifiedAt), so each iteration re-reads page 0; ITERATION_LIMIT bounds it.
 * Not multi-instance safe: two instances on this cron both scan and can both notify; the fix is ShedLock, which is not a dependency here.
 */
@Component
@RequiredArgsConstructor
public class CrmFollowUpScheduler {

    private final CrmActivityRepository crmActivityRepository;
    private final LeadRepository leadRepository;
    private final OpportunityRepository opportunityRepository;
    private final NotificationService notificationService;
    private final TransactionTemplate transactionTemplate;

    private static final List<LeadStatus> LEAD_CLOSED_STATUSES = List.of(LeadStatus.DISQUALIFIED);
    private static final List<OpportunityStage> OPP_CLOSED_STAGES =
            List.of(OpportunityStage.WON, OpportunityStage.LOST);

    /** Rows handled per transaction. */
    private static final int BATCH_SIZE = 200;

    /** Safety net: bounds the re-read loop at BATCH_SIZE * this many rows per run. */
    private static final int ITERATION_LIMIT = 500;

    @Scheduled(cron = "0 */30 * * * *")
    public void notifyDueFollowUps() {
        LocalDateTime now = LocalDateTime.now();
        for (int i = 0; i < ITERATION_LIMIT; i++) {
            // TransactionTemplate, not a self-invoked @Transactional method: that skips the proxy, so the stamping would never commit.
            boolean more = Boolean.TRUE.equals(
                    transactionTemplate.execute(status -> notifyDueFollowUpBatch(now)));
            if (!more) {
                return;
            }
        }
    }

    /** @return true if a full batch was handled, i.e. there may be more. */
    private boolean notifyDueFollowUpBatch(LocalDateTime now) {
        // The followUpNotifiedAt filter fires this once per follow-up (without it, 48 re-notifications a day) and drops handled rows out of page 0.
        List<CrmActivity> due = crmActivityRepository
                .findByFollowUpAtLessThanEqualAndFollowUpDoneFalseAndFollowUpNotifiedAtIsNullAndDeletedFalse(
                        now, PageRequest.of(0, BATCH_SIZE));

        for (CrmActivity activity : due) {
            // Stamped before the null-recipient skip, or an ownerless follow-up is re-scanned forever.
            activity.setFollowUpNotifiedAt(now);

            if (activity.getPerformedBy() == null) continue;

            String subject = activity.getLead() != null ? activity.getLead().getContactName()
                    : activity.getOpportunity() != null ? activity.getOpportunity().getName()
                    : activity.getClient() != null ? activity.getClient().getClientCompanyName()
                    : activity.getSubject();

            // Land the user on the record the follow-up is about, not a fixed page.
            String link = activity.getOpportunity() != null ? "/crm/pipeline"
                    : activity.getClient() != null ? "/crm/clients"
                    : "/crm/leads";

            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.FOLLOW_UP_DUE,
                    "Follow-up due",
                    "Follow-up \"" + activity.getSubject() + "\" for " + subject + " is due.",
                    link,
                    activity.getPerformedBy().getId(),
                    activity.getCompany().getId()
            ));
        }
        return due.size() == BATCH_SIZE;
    }

    // Daily, not every 30 minutes: staleness is a slow-moving signal, unlike a follow-up's exact due timestamp.
    @Scheduled(cron = "0 0 9 * * *")
    public void notifyStalePipeline() {
        LocalDate leadCutoff = LocalDate.now().minusDays(30);
        for (int i = 0; i < ITERATION_LIMIT; i++) {
            if (!Boolean.TRUE.equals(transactionTemplate.execute(s -> notifyStaleLeadBatch(leadCutoff)))) break;
        }

        LocalDateTime oppCutoff = LocalDateTime.now().minusDays(14);
        for (int i = 0; i < ITERATION_LIMIT; i++) {
            if (!Boolean.TRUE.equals(transactionTemplate.execute(s -> notifyStaleOpportunityBatch(oppCutoff)))) break;
        }
    }

    private boolean notifyStaleLeadBatch(LocalDate cutoff) {
        // Also picks up never-contacted leads via createdAt: `lastContactDate < cutoff` is never true for null.
        List<Lead> stale = leadRepository
                .findNewlyStaleLeads(cutoff, cutoff.atStartOfDay(), LEAD_CLOSED_STATUSES,
                        PageRequest.of(0, BATCH_SIZE))
                .getContent();

        for (Lead lead : stale) {
            lead.setStaleNotifiedAt(LocalDateTime.now());
            if (lead.getAssignedTo() == null || lead.getAssignedTo().getUser() == null) continue;
            // "since <date>" reads as a lie when lastContactDate is null, which now reaches here.
            String since = lead.getLastContactDate() != null
                    ? "hasn't been contacted since " + lead.getLastContactDate()
                    : "has never been contacted";
            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.FOLLOW_UP_DUE,
                    "Lead has gone stale",
                    lead.getContactName() + " " + since + " - it may need a follow-up.",
                    "/crm/leads",
                    lead.getAssignedTo().getUser().getId(),
                    lead.getCompany().getId()
            ));
        }
        return stale.size() == BATCH_SIZE;
    }

    private boolean notifyStaleOpportunityBatch(LocalDateTime cutoff) {
        List<Opportunity> stale = opportunityRepository
                .findNewlyStaleOpportunities(OPP_CLOSED_STAGES, cutoff, PageRequest.of(0, BATCH_SIZE))
                .getContent();

        for (Opportunity opportunity : stale) {
            opportunity.setStaleNotifiedAt(LocalDateTime.now());
            if (opportunity.getOwner() == null || opportunity.getOwner().getUser() == null) continue;
            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.FOLLOW_UP_DUE,
                    "Deal has gone stale",
                    opportunity.getName() + " has had no activity in over 14 days - it may be going cold.",
                    "/crm/pipeline",
                    opportunity.getOwner().getUser().getId(),
                    opportunity.getCompany().getId()
            ));
        }
        return stale.size() == BATCH_SIZE;
    }
}
