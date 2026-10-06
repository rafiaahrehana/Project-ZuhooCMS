package com.zuhoocms.modules.itam.software;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface SoftwareLicenseSeatRepository extends JpaRepository<SoftwareLicenseSeat, Long> {

    /** Active seat holders of a licence, with the licence fetched in the same query (no N+1). */
    @Query("SELECT s FROM SoftwareLicenseSeat s JOIN FETCH s.license l " +
           "WHERE l.id = :licenseId AND s.releasedAt IS NULL ORDER BY s.assignedAt ASC, s.id ASC")
    List<SoftwareLicenseSeat> findActiveByLicenseId(@Param("licenseId") Long licenseId);

    /** Seats an employee currently holds, licence fetched in the same query (no N+1). */
    @Query("SELECT s FROM SoftwareLicenseSeat s JOIN FETCH s.license l " +
           "WHERE s.employee.id = :employeeId AND s.companyId = :companyId AND s.releasedAt IS NULL " +
           "ORDER BY s.assignedAt ASC, s.id ASC")
    List<SoftwareLicenseSeat> findActiveByEmployeeIdAndCompanyId(@Param("employeeId") Long employeeId,
                                                                 @Param("companyId") Long companyId);

    /** The real "seats used" figure - the licence's own seatsUsed column is only a cache. */
    long countByLicenseIdAndReleasedAtIsNull(Long licenseId);

    long countByEmployeeIdAndCompanyIdAndReleasedAtIsNull(Long employeeId, Long companyId);

    /** [licenseId, activeSeatCount] for a page of licences, in one query. */
    @Query("SELECT s.license.id, COUNT(s) FROM SoftwareLicenseSeat s " +
           "WHERE s.license.id IN :licenseIds AND s.releasedAt IS NULL GROUP BY s.license.id")
    List<Object[]> countActiveByLicenseIds(@Param("licenseIds") Collection<Long> licenseIds);

    Optional<SoftwareLicenseSeat> findByLicenseIdAndEmployeeIdAndReleasedAtIsNull(Long licenseId, Long employeeId);
}
