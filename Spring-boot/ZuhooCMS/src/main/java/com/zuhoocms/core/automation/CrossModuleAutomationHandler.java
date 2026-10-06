package com.zuhoocms.core.automation;

import com.zuhoocms.modules.servicedesk.billing.UsageBillingService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;


@Slf4j
@Component
@RequiredArgsConstructor
public class CrossModuleAutomationHandler {

    private final UsageBillingService usageBillingService;

    @Async
    @EventListener
    public void onServiceRequestCompleted(ServiceRequestCompletedEvent event) {
        try {
            usageBillingService.handleCompletion(event.getServiceRequestId(), event.getCompanyId());
        } catch (Exception ex) {
            log.error("UsageBilling failed for request {}: {}",
                event.getServiceRequestId(), ex.getMessage(), ex);
        }
    }

    @Async
    @EventListener
    public void onOpportunityWon(OpportunityWonEvent event) {
        try {
            log.info("[Automation] Opportunity WON: id={} client={} company={} name='{}'",
                event.getOpportunityId(), event.getClientId(),
                event.getCompanyId(), event.getOpportunityName());
            // TODO: call ServiceRequestService.createIntake(event) once a Welcome Intake workflow template exists.
        } catch (Exception ex) {
            log.error("[Automation] Opportunity WON handler failed for opportunity {}: {}",
                event.getOpportunityId(), ex.getMessage(), ex);
        }
    }
}
