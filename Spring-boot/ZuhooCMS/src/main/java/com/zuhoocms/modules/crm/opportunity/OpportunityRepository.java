package com.zuhoocms.modules.crm.opportunity;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface OpportunityRepository extends JpaRepository<Opportunity, Long> {

    Optional<Opportunity> findByIdAndCompanyId(Long id, Long companyId);

    Page<Opportunity> findByCompanyId(Long companyId, Pageable pageable);

    Page<Opportunity> findByCompanyIdAndStage(Long companyId, OpportunityStage stage, Pageable pageable);

    Page<Opportunity> findByCompanyIdAndClientId(Long companyId, Long clientId, Pageable pageable);

    long countByCompanyIdAndClientIdAndStageNotIn(Long companyId, Long clientId, List<OpportunityStage> stages);

    Page<Opportunity> findByCompanyIdAndOwnerId(Long companyId, Long ownerId, Pageable pageable);

    Page<Opportunity> findByCompanyIdAndTagsId(Long companyId, Long tagId, Pageable pageable);

    List<Opportunity> findByCompanyIdAndStageNotInOrderByExpectedCloseDateAsc(Long companyId, List<OpportunityStage> stages);

    // Paged counterpart for the pipeline list's default view: what is still in play, without a year of closed deals in front of it.
    Page<Opportunity> findByCompanyIdAndStageNotIn(Long companyId, List<OpportunityStage> stages, Pageable pageable);

    @Query("SELECT o FROM Opportunity o WHERE o.company.id = :companyId AND " +
           "(LOWER(o.name) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(o.client.clientCompanyName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!') AND " +
           "o.deleted = false")
    Page<Opportunity> searchOpportunities(@Param("companyId") Long companyId, @Param("keyword") String keyword, Pageable pageable);

    // Open deals with no activity since :cutoff (or never, and created before it)
    @Query("SELECT o FROM Opportunity o WHERE o.company.id = :companyId " +
           "AND o.stage NOT IN :closedStages AND o.deleted = false " +
           "AND ((o.lastActivityAt IS NOT NULL AND o.lastActivityAt < :cutoff) " +
           "OR (o.lastActivityAt IS NULL AND o.createdAt < :cutoff)) " +
           "ORDER BY o.lastActivityAt ASC")
    List<Opportunity> findStaleOpenOpportunities(@Param("companyId") Long companyId,
        @Param("closedStages") List<OpportunityStage> closedStages,
        @Param("cutoff") java.time.LocalDateTime cutoff, Pageable pageable);

    // Cross-company: runs from a scheduler with no request context, as in LicenseExpiryScheduler. staleNotifiedAt IS NULL makes it fire once per staleness period, not every run.
    @Query("SELECT o FROM Opportunity o WHERE o.stage NOT IN :closedStages AND o.deleted = false " +
           "AND ((o.lastActivityAt IS NOT NULL AND o.lastActivityAt < :cutoff) " +
           "OR (o.lastActivityAt IS NULL AND o.createdAt < :cutoff)) " +
           "AND o.staleNotifiedAt IS NULL AND o.owner IS NOT NULL")
    // Paged: unpaged, the scheduler loaded every company's matching rows into one transaction, growing without bound as tenants are added.
    Page<Opportunity> findNewlyStaleOpportunities(@Param("closedStages") List<OpportunityStage> closedStages,
        @Param("cutoff") java.time.LocalDateTime cutoff, Pageable pageable);

    // Pipeline summary per stage; the divisor is the integer 100, not 100.0, which promoted the expression to floating point and returned 1234.5600000000002.
    @Query("SELECT o.stage AS stage, COUNT(o) AS dealCount, " +
           "COALESCE(SUM(o.amount), 0) AS totalAmount, " +
           "COALESCE(SUM(o.amount * o.probability / 100), 0) AS weightedAmount " +
           "FROM Opportunity o WHERE o.company.id = :companyId AND o.deleted = false " +
           "GROUP BY o.stage")
    List<PipelineStageSummary> summarizePipeline(@Param("companyId") Long companyId);

    @Query("SELECT COALESCE(SUM(o.amount), 0) FROM Opportunity o WHERE o.company.id = :companyId AND " +
           "o.stage = 'WON' AND o.actualCloseDate BETWEEN :from AND :to AND o.deleted = false")
    java.math.BigDecimal sumWonAmountBetween(@Param("companyId") Long companyId,
        @Param("from") java.time.LocalDate from, @Param("to") java.time.LocalDate to);

    @Query("SELECT COALESCE(SUM(o.amount), 0) FROM Opportunity o WHERE o.company.id = :companyId AND " +
           "o.stage NOT IN ('WON', 'LOST') AND o.deleted = false")
    java.math.BigDecimal sumOpenPipelineValue(@Param("companyId") Long companyId);

    long countByCompanyId(Long companyId);

    long countByCompanyIdAndStage(Long companyId, OpportunityStage stage);

    long countByCompanyIdAndStageNotIn(Long companyId, List<OpportunityStage> stages);

    @Query("SELECT COALESCE(SUM(o.amount), 0) FROM Opportunity o WHERE o.company.id = :companyId AND " +
           "o.stage = :stage AND o.deleted = false")
    java.math.BigDecimal sumAmountByCompanyIdAndStage(@Param("companyId") Long companyId, @Param("stage") OpportunityStage stage);

    interface PipelineStageSummary {
        OpportunityStage getStage();
        Long getDealCount();
        java.math.BigDecimal getTotalAmount();
        java.math.BigDecimal getWeightedAmount();
    }
    java.util.List<Opportunity> findTop5ByCompanyIdOrderByUpdatedAtDesc(Long companyId);
}
