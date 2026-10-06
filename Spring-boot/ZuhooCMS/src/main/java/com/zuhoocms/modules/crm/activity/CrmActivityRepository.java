package com.zuhoocms.modules.crm.activity;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface CrmActivityRepository extends JpaRepository<CrmActivity, Long> {

    Optional<CrmActivity> findByIdAndCompanyId(Long id, Long companyId);

    Page<CrmActivity> findByCompanyIdAndClientIdOrderByActivityDateDesc(Long companyId, Long clientId, Pageable pageable);

    Page<CrmActivity> findByCompanyIdAndOpportunityIdOrderByActivityDateDesc(Long companyId, Long opportunityId, Pageable pageable);

    Page<CrmActivity> findByCompanyIdOrderByActivityDateDesc(Long companyId, Pageable pageable);

    Page<CrmActivity> findByLeadIdAndCompanyId(Long leadId, Long companyId, Pageable pageable);

    // No companyId scoping: runs from a scheduler with no request context, so the tenant Hibernate filter is inactive, as in the SLA/invoice schedulers.
    List<CrmActivity> findByFollowUpAtLessThanEqualAndFollowUpDoneFalseAndDeletedFalse(LocalDateTime cutoff);

    /** Due, still open and not yet notified - the set the scheduler acts on; paged because unpaged it loaded every company's outstanding follow-ups into one transaction. */
    List<CrmActivity> findByFollowUpAtLessThanEqualAndFollowUpDoneFalseAndFollowUpNotifiedAtIsNullAndDeletedFalse(
            LocalDateTime cutoff, Pageable pageable);

    // Pageable, so the dashboard's five-row widget asks for five rows instead of the company's whole follow-up backlog.
    List<CrmActivity> findByCompanyIdAndFollowUpDoneFalseAndFollowUpAtGreaterThanEqualOrderByFollowUpAtAsc(
            Long companyId, LocalDateTime from, Pageable pageable);
}
