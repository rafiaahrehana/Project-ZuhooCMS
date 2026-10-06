package com.zuhoocms.modules.crm.opportunity;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface OpportunityService {

    OpportunityResponse create(OpportunityRequest request);

    OpportunityResponse createFromLead(Long leadId, OpportunityRequest request);

    Page<OpportunityResponse> listAll(OpportunityStage stage, Boolean openOnly, Long clientId, Long ownerId, Long tagId, String keyword, Pageable pageable);

    OpportunityResponse getById(Long id);

    OpportunityResponse update(Long id, OpportunityRequest request);

    OpportunityResponse changeStage(Long id, ChangeStageRequest request);

    // Previews whether moving a client-less Opportunity to WON would auto-link an existing Client; null means no pending transition or no match.
    com.zuhoocms.modules.crm.duplicate.DuplicateMatch previewWonDuplicate(Long id);

    PipelineSummaryResponse getPipelineSummary();

    void delete(Long id);
}
