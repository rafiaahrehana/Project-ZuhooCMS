package com.zuhoocms.modules.crm.lead;

import com.zuhoocms.enums.LeadSource;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.enums.Priority;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface LeadService {

    LeadResponse createLead(LeadRequest request);

    LeadResponse getLeadById(Long id);

    Page<LeadResponse> listLeads(LeadStatus status, Pageable pageable);

    Page<LeadResponse> listMyLeads(Pageable pageable);

    // LeadUpdateRequest, not LeadRequest: PATCH must not carry creation-only constraints (see LeadUpdateRequest).
    LeadResponse updateLead(Long id, LeadUpdateRequest request);

    void deleteLead(Long id);

    Page<LeadResponse> searchLeads(String keyword, Pageable pageable);

    Page<LeadResponse> filterLeads(LeadFilterRequest filter, Pageable pageable);

    Page<LeadResponse> findLeadsBySource(LeadSource source, Pageable pageable);

    Page<LeadResponse> findLeadsByPriority(Priority priority, Pageable pageable);

    Page<LeadResponse> findUnassignedLeads(Long companyId, Pageable pageable);

    Page<LeadResponse> findHighPriorityOpenLeads(Long companyId, Pageable pageable);

    Page<LeadResponse> findNeverContactedLeads(Pageable pageable);

    Page<LeadResponse> findStalLeads(Pageable pageable);

    // No Client is created here: that happens when the Opportunity reaches Won (see OpportunityService.changeStage).
    com.zuhoocms.modules.crm.opportunity.OpportunityResponse convertToOpportunity(Long id, ConvertToOpportunityRequest request);

    com.zuhoocms.modules.crm.activity.CrmActivityResponse addActivity(Long leadId, com.zuhoocms.modules.crm.activity.CrmActivityRequest request);

    Page<com.zuhoocms.modules.crm.activity.CrmActivityResponse> getActivities(Long leadId, Pageable pageable);

    void deleteActivity(Long leadId, Long activityId);

    long countLeadsByStatus(LeadStatus status);

    long countActiveLeads();

    long countMyActiveLeads();

    LeadResponse summariseLead(Long id);
}
