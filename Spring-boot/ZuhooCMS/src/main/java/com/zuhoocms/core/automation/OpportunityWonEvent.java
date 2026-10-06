package com.zuhoocms.core.automation;

import lombok.Getter;

/** Published when an Opportunity moves to WON, for cross-module automation such as creating a service-request intake. */
@Getter
public class OpportunityWonEvent extends BusinessEvent {

    private final Long opportunityId;
    private final Long clientId;
    private final String opportunityName;

    public OpportunityWonEvent(Object source, Long companyId,
                               Long opportunityId, Long clientId,
                               String opportunityName) {
        super(source, companyId, "OPPORTUNITY_WON");
        this.opportunityId = opportunityId;
        this.clientId = clientId;
        this.opportunityName = opportunityName;
    }
}
