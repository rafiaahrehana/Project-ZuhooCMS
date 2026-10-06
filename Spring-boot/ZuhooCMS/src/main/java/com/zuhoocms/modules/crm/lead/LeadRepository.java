package com.zuhoocms.modules.crm.lead;

import com.zuhoocms.enums.LeadSource;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.enums.Priority;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface LeadRepository extends JpaRepository<Lead, Long> {

    Optional<Lead> findByIdAndCompanyId(Long id, Long companyId);

    /** Row-locking read for the lead -> opportunity conversion: {@code createFromLead}'s isConverted() check is check-then-act, so concurrent converts both created an opportunity. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT l FROM Lead l WHERE l.id = :id AND l.company.id = :companyId")
    Optional<Lead> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    Page<Lead> findByCompanyId(Long companyId, Pageable pageable);

    Page<Lead> findByCompanyIdAndStatus(Long companyId, LeadStatus status, Pageable pageable);

    Page<Lead> findByCompanyIdAndAssignedToId(Long companyId, Long employeeId, Pageable pageable);


    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "(LOWER(l.contactName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(l.email) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(l.phone) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(l.companyName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!') AND " +
           "l.deleted = false")
    Page<Lead> searchLeads(@Param("companyId") Long companyId, @Param("keyword") String keyword, Pageable pageable);

    Page<Lead> findByCompanyIdAndSource(Long companyId, LeadSource source, Pageable pageable);

    Page<Lead> findByCompanyIdAndPriority(Long companyId, Priority priority, Pageable pageable);


    /**
     * Every filter the Leads screen offers, applied together: the keyword is one predicate, not a short-circuit that dropped the other selections.
     *
     * Boolean views arrive as pairs of primitive flags, because a nullable Boolean compared against a literal in JPQL is ambiguous once null.
     * No ORDER BY: the caller's validated Pageable governs ordering (see CrmSortWhitelist).
     */
    @Query("SELECT DISTINCT l FROM Lead l LEFT JOIN l.tags t WHERE l.company.id = :companyId " +
           "AND (:status IS NULL OR l.status = :status) " +
           "AND (:source IS NULL OR l.source = :source) " +
           "AND (:priority IS NULL OR l.priority = :priority) " +
           "AND (:assignedToId IS NULL OR l.assignedTo.id = :assignedToId) " +
           "AND (:tagId IS NULL OR t.id = :tagId) " +
           // Empty string, not null, means "no keyword": an untyped null in LOWER(CONCAT('%', ?, '%')) is sent as bytea and fails with "function lower(bytea) does not exist".
           "AND (:keyword = '' OR " +
           "     LOWER(l.contactName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "     LOWER(l.email) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "     LOWER(l.phone) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "     LOWER(l.companyName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!') " +
           // Flag + sentinel date, as for the keyword: a null date reaches Postgres untyped ("could not determine data type of parameter"), and the flag decides whether the predicate applies.
           "AND (:closeFromSet = false OR (l.expectedCloseDate IS NOT NULL AND l.expectedCloseDate >= :closeFrom)) " +
           "AND (:closeToSet = false OR (l.expectedCloseDate IS NOT NULL AND l.expectedCloseDate <= :closeTo)) " +
           "AND (:withActivityOnly = false OR l.lastActivityAt IS NOT NULL) " +
           "AND (:withoutActivityOnly = false OR l.lastActivityAt IS NULL) " +
           "AND (:convertedOnly = false OR l.converted = true) " +
           "AND (:notConvertedOnly = false OR l.converted = false) " +
           "AND (:unassignedOnly = false OR l.assignedTo IS NULL) " +
           "AND (:highPriorityOnly = false OR l.priority = com.zuhoocms.enums.Priority.HIGH) " +
           "AND (:openOnly = false OR (l.converted = false AND l.status <> com.zuhoocms.enums.LeadStatus.DISQUALIFIED)) " +
           "AND l.deleted = false")
    Page<Lead> filterLeads(@Param("companyId") Long companyId,
                           @Param("status") LeadStatus status,
                           @Param("source") LeadSource source,
                           @Param("priority") Priority priority,
                           @Param("assignedToId") Long assignedToId,
                           @Param("tagId") Long tagId,
                           @Param("keyword") String keyword,
                           @Param("closeFromSet") boolean closeFromSet,
                           @Param("closeFrom") LocalDate closeFrom,
                           @Param("closeToSet") boolean closeToSet,
                           @Param("closeTo") LocalDate closeTo,
                           @Param("withActivityOnly") boolean withActivityOnly,
                           @Param("withoutActivityOnly") boolean withoutActivityOnly,
                           @Param("convertedOnly") boolean convertedOnly,
                           @Param("notConvertedOnly") boolean notConvertedOnly,
                           @Param("unassignedOnly") boolean unassignedOnly,
                           @Param("highPriorityOnly") boolean highPriorityOnly,
                           @Param("openOnly") boolean openOnly,
                           Pageable pageable);

    // converted=false matters because LeadStatus has no CONVERTED value: a converted QUALIFIED lead keeps that status, so counting by status alone only ever grew.
    long countByCompanyIdAndStatusAndConvertedFalse(Long companyId, LeadStatus status);

    long countByCompanyIdAndSource(Long companyId, com.zuhoocms.enums.LeadSource source);

    long countByCompanyIdAndStatusAndCreatedAtBetween(
            Long companyId, LeadStatus status, LocalDateTime from, LocalDateTime to);

    @Query("SELECT COUNT(l) FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.status NOT IN :closedStatuses AND l.converted = false AND l.deleted = false")
    long countActiveByCompanyId(@Param("companyId") Long companyId,
                                @Param("closedStatuses") List<LeadStatus> closedStatuses);

    @Query("SELECT COUNT(l) FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.assignedTo.id = :assignedToId AND l.status NOT IN :closedStatuses AND l.converted = false AND l.deleted = false")
    long countActiveByAssignee(@Param("companyId") Long companyId,
                               @Param("assignedToId") Long assignedToId,
                               @Param("closedStatuses") List<LeadStatus> closedStatuses);


    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.expectedCloseDate BETWEEN :startDate AND :endDate AND " +
           "l.deleted = false")
    List<Lead> findLeadsCloseExpectedBetween(@Param("companyId") Long companyId,
                                             @Param("startDate") LocalDate startDate,
                                             @Param("endDate") LocalDate endDate);

    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.lastContactDate IS NULL AND l.status != 'DISQUALIFIED' AND l.converted = false AND " +
           "l.deleted = false")
    Page<Lead> findNeverContactedLeads(@Param("companyId") Long companyId, Pageable pageable);

    // Falls back to createdAt because `lastContactDate < :beforeDate` is never true for NULL, so never-contacted leads fell out of this query entirely.
    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "(l.lastContactDate < :beforeDate OR " +
           " (l.lastContactDate IS NULL AND l.createdAt < :beforeCreated)) AND " +
           "l.status NOT IN :closedStatuses AND l.converted = false AND " +
           "l.deleted = false")
    // Same cutoff passed twice: Hibernate 7 throws InvalidDataAccessApiUsageException comparing the DATE lastContactDate against a LocalDateTime, and createdAt is a timestamp.
    Page<Lead> findStalLeads(@Param("companyId") Long companyId,
                             @Param("beforeDate") java.time.LocalDate beforeDate,
                             @Param("beforeCreated") LocalDateTime beforeCreated,
                             @Param("closedStatuses") List<LeadStatus> closedStatuses,
                             Pageable pageable);

    // Cross-company: runs from a scheduler with no request context, as in LicenseExpiryScheduler. staleNotifiedAt IS NULL makes it fire once per staleness period, not every run.
    // Paged so the scheduler does not pull every company's matching rows into one transaction (see CrmFollowUpScheduler), and NULL-tolerant like findStalLeads.
    @Query("SELECT l FROM Lead l WHERE " +
           "(l.lastContactDate < :beforeDate OR " +
           " (l.lastContactDate IS NULL AND l.createdAt < :beforeCreated)) AND " +
           "l.status NOT IN :closedStatuses AND l.converted = false AND " +
           "l.deleted = false AND l.staleNotifiedAt IS NULL AND l.assignedTo IS NOT NULL")
    Page<Lead> findNewlyStaleLeads(@Param("beforeDate") java.time.LocalDate beforeDate,
                                    @Param("beforeCreated") LocalDateTime beforeCreated,
                                    @Param("closedStatuses") List<LeadStatus> closedStatuses,
                                    Pageable pageable);

    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.assignedTo IS NULL AND l.status NOT IN :closedStatuses AND l.converted = false AND " +
           "l.deleted = false")
    Page<Lead> findUnassignedLeads(@Param("companyId") Long companyId,
                                   @Param("closedStatuses") List<LeadStatus> closedStatuses,
                                   Pageable pageable);

    @Query("SELECT l FROM Lead l WHERE l.company.id = :companyId AND " +
           "l.priority = 'HIGH' AND l.status NOT IN :closedStatuses AND l.converted = false AND " +
           "l.deleted = false " +
           "ORDER BY l.expectedCloseDate ASC")
    Page<Lead> findHighPriorityOpenLeads(@Param("companyId") Long companyId,
                                         @Param("closedStatuses") List<LeadStatus> closedStatuses,
                                         Pageable pageable);

    /** Case-insensitive email dedupe, optionally excluding the row being edited: a case-sensitive query let "Bob@X.com" and "bob@x.com" be two leads. Emails are normalised on write too (see EmailMatching). */
    @Query("SELECT COUNT(l) > 0 FROM Lead l WHERE l.company.id = :companyId AND l.deleted = false " +
           "AND LOWER(l.email) = LOWER(:email) AND (:excludeId IS NULL OR l.id <> :excludeId)")
    boolean existsByEmailIgnoringCase(@Param("email") String email,
                                      @Param("companyId") Long companyId,
                                      @Param("excludeId") Long excludeId);

    /** Phone dedupe on trailing digits (see PhoneMatching.matchKey), so "+966 50 123 4567" and "0501234567" match despite punctuation, country code and trunk prefix. */
    @Query(value = "SELECT EXISTS (SELECT 1 FROM leads l WHERE l.company_id = :companyId AND l.deleted = false "
            + "AND l.phone IS NOT NULL "
            + "AND regexp_replace(l.phone, '[^0-9]', '', 'g') <> '' "
            + "AND regexp_replace(l.phone, '[^0-9]', '', 'g') LIKE ('%' || :suffix) "
            + "AND (CAST(:excludeId AS bigint) IS NULL OR l.id <> CAST(:excludeId AS bigint)))",
           nativeQuery = true)
    boolean existsByNormalisedPhone(@Param("suffix") String suffix,
                                    @Param("companyId") Long companyId,
                                    @Param("excludeId") Long excludeId);

    long countByCompanyId(Long companyId);

    long countByCompanyIdAndConvertedTrue(Long companyId);

    /** Lead counts per source in ONE grouped query; the dashboard used to call {@code countByCompanyIdAndSource} once per LeadSource constant. */
    @Query("SELECT l.source AS source, COUNT(l) AS total FROM Lead l " +
           "WHERE l.company.id = :companyId AND l.deleted = false GROUP BY l.source")
    List<LeadSourceCount> countByCompanyIdGroupedBySource(@Param("companyId") Long companyId);

    interface LeadSourceCount {
        LeadSource getSource();
        Long getTotal();
    }
}
