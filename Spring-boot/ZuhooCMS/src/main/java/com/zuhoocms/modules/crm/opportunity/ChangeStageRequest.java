package com.zuhoocms.modules.crm.opportunity;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.Setter;

@Getter @Setter
public class ChangeStageRequest {

    @NotNull(message = "Stage is required")
    private OpportunityStage stage;

    // Required when moving to LOST: the code carries the analysis, the text is detail, mandatory only for OTHER.
    private com.zuhoocms.enums.LostReason lostReasonCode;

    @Size(max = 255)
    private String lostReason;

    /** Optional per-deal override: omitted, the new stage's default applies (what the pipeline board sends on a drag); supplied, the rep's own figure survives later moves. */
    @jakarta.validation.constraints.Min(0)
    @jakarta.validation.constraints.Max(100)
    private Integer probability;

    // Populated by the duplicate-detection modal when moving a client-less Opportunity to WON: link an existing Client match, or force-create a new one.
    private Long linkToExistingClientId;
    private boolean forceCreateNewClient;
}
