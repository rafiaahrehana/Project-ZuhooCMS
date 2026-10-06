package com.zuhoocms.modules.hrm.recruitment.jobapplication;

import com.zuhoocms.enums.ApplicationStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface JobApplicationRepository extends JpaRepository<JobApplication, Long> {

    Optional<JobApplication> findByIdAndCompanyId(Long id, Long companyId);

    Page<JobApplication> findByCompanyId(Long companyId, Pageable pageable);

    /** Unpaged - used by RecruitmentKpiServiceImpl, which aggregates in Java over the full set rather than issuing one query per breakdown. */
    List<JobApplication> findByCompanyId(Long companyId);

    Page<JobApplication> findByCompanyIdAndJobPostingId(
        Long companyId, Long jobPostingId, Pageable pageable);

    Page<JobApplication> findByCompanyIdAndStatus(
        Long companyId, ApplicationStatus status, Pageable pageable);

    // Excluded statuses let a rejected/withdrawn candidate reapply; otherwise HR's only recourse for a corrected resubmission was deleting the old record.
    boolean existsByJobPostingIdAndCandidateIdAndStatusNotIn(
        Long jobPostingId, Long candidateId, List<ApplicationStatus> excludedStatuses);

    List<JobApplication> findByCompanyIdAndCandidateId(Long companyId, Long candidateId);

    long countByCompanyIdAndCandidateId(Long companyId, Long candidateId);

    /**
     * Copies a candidate's contact details onto their applications, run just before the candidate row is soft-deleted.
     * Every later read of those applications (list, detail, offers, interviews, KPIs, talent pool) sees a lazy
     * candidate proxy that throws under BaseEntity's {@code @SQLRestriction("deleted = false")}, or a null
     * association when the query left-join-fetched it; applicantName/applicantPhone are the denormalised fallback,
     * so one UPDATE here keeps the name on every one of those paths without a lookup per row.
     * COALESCE so a careers-page submission's own details are never overwritten by the shared Candidate record.
     */
    @org.springframework.data.jpa.repository.Modifying
    @Query("""
        UPDATE JobApplication a
        SET a.applicantName = COALESCE(a.applicantName, :name),
            a.applicantPhone = COALESCE(a.applicantPhone, :phone)
        WHERE a.company.id = :companyId AND a.candidate.id = :candidateId
        """)
    int backfillApplicantDetails(@Param("companyId") Long companyId, @Param("candidateId") Long candidateId,
                                 @Param("name") String name, @Param("phone") String phone);

    long countByCompanyIdAndJobPostingId(Long companyId, Long jobPostingId);

    long countByCompanyIdAndStatus(Long companyId, com.zuhoocms.enums.ApplicationStatus status);

    long countByCompanyIdAndJobPostingIdAndStatus(Long companyId, Long jobPostingId, com.zuhoocms.enums.ApplicationStatus status);

    /** Row lock on the application - serialises offer creation so two concurrent creates can't both pass the one-live-offer check. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT a FROM JobApplication a WHERE a.id = :id AND a.company.id = :companyId")
    Optional<JobApplication> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    /** KPI report: every application with the associations the report reads, in one query (no N+1). */
    @Query("""
        SELECT a FROM JobApplication a
        LEFT JOIN FETCH a.candidate
        LEFT JOIN FETCH a.jobPosting
        WHERE a.company.id = :companyId
        """)
    List<JobApplication> findAllForKpis(@Param("companyId") Long companyId);

    /**
     * Application id -> candidate id for the KPI report, read straight off the candidate_id FK column.
     *
     * <p>Not derivable from {@link #findAllForKpis}: that query LEFT JOIN FETCHes the candidate, and BaseEntity's
     * {@code @SQLRestriction("deleted = false")} makes the fetched association plain {@code null} once the candidate
     * is soft-deleted - there is no proxy left to read an id off, so the distinct-candidate count could no longer see
     * the FK and reported 0 candidates against a non-zero application count. A deleted candidate's applications still
     * happened, so the count has to come from a path the soft-delete filter cannot reach: {@code a.candidate.id} is a
     * plain FK read, so it resolves without joining (and therefore without restricting) the candidates table, while
     * the restriction on JobApplication itself still applies and keeps deleted applications out.
     */
    @Query("SELECT a.id, a.candidate.id FROM JobApplication a WHERE a.company.id = :companyId")
    List<Object[]> findCandidateIdsByApplication(@Param("companyId") Long companyId);

    /** Application counts per status in one grouped query - the HR dashboard pipeline. */
    @Query("SELECT a.status, COUNT(a) FROM JobApplication a WHERE a.company.id = :companyId GROUP BY a.status")
    List<Object[]> countByStatus(@Param("companyId") Long companyId);

    /** Applications that had at least one interview actually held (COMPLETED), whatever their current status. */
    @Query("""
        SELECT DISTINCT i.jobApplication.id FROM Interview i
        WHERE i.company.id = :companyId
          AND i.status = com.zuhoocms.modules.hrm.recruitment.interview.Interview.Status.COMPLETED
        """)
    List<Long> findInterviewedApplicationIds(@Param("companyId") Long companyId);
}
