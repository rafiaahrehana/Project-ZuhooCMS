package com.zuhoocms.modules.servicedesk.servicereview;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

/** findByHubServiceId and findAverageRatingByServiceId are intentionally unscoped: they serve the public per-service view of published reviews. */
public interface ServiceReviewRepository extends JpaRepository<ServiceReview, Long> {

    Page<ServiceReview> findByCompanyId(Long companyId, Pageable pageable);

    Optional<ServiceReview> findByIdAndCompanyId(Long id, Long companyId);

    Page<ServiceReview> findByHubServiceId(Long hubServiceId, Pageable pageable);

    /** Tenant-scoped reviews of one service (the unscoped variant let any tenant walk service ids). */
    Page<ServiceReview> findByCompanyIdAndHubServiceId(Long companyId, Long hubServiceId, Pageable pageable);

    @Query("SELECT AVG(r.rating) FROM ServiceReview r " +
            "WHERE r.company.id = :companyId " +
            "AND r.hubService.id = :serviceId " +
            "AND r.published = true AND r.deleted = false")
    Optional<Double> findAverageRatingByCompanyIdAndServiceId(@Param("companyId") Long companyId,
                                                              @Param("serviceId") Long serviceId);

    Optional<ServiceReview> findByServiceRequestIdAndClientId(Long serviceRequestId, Long clientId);

    @Query("SELECT AVG(r.rating) FROM ServiceReview r " +
            "WHERE r.hubService.id = :serviceId " +
            "AND r.published = true AND r.deleted = false")
    Optional<Double> findAverageRatingByServiceId(@Param("serviceId") Long serviceId);

    @Query("SELECT AVG(r.rating) FROM ServiceReview r " +
            "WHERE r.company.id = :companyId " +
            "AND r.published = true AND r.deleted = false")
    Optional<Double> findAverageRatingByCompanyId(@Param("companyId") Long companyId);

    /** Average client rating for one staff member in a window (the performance-review CSAT KPI); unpublished reviews excluded, as above. */
    @Query("""
        SELECT AVG(r.rating) FROM ServiceReview r
        WHERE r.company.id = :companyId
          AND r.staff.id = :staffId
          AND r.createdAt >= :from AND r.createdAt < :to
          AND r.published = true AND r.deleted = false
        """)
    Optional<Double> findAverageRatingByStaffInRange(
        @Param("companyId") Long companyId,
        @Param("staffId") Long staffId,
        @Param("from") java.time.LocalDateTime from,
        @Param("to") java.time.LocalDateTime to);
}
