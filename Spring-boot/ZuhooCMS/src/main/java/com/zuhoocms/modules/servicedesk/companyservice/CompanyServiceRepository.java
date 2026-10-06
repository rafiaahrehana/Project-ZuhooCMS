package com.zuhoocms.modules.servicedesk.companyservice;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CompanyServiceRepository extends JpaRepository<CompanyService, Long> {

    Page<CompanyService> findByCompanyId(Long companyId, Pageable pageable);

    Page<CompanyService> findByCompanyIdAndCategoryId(Long companyId, Long categoryId, Pageable pageable);

    List<CompanyService> findByCompanyIdAndActiveTrue(Long companyId);

    Optional<CompanyService> findByIdAndCompanyId(Long id, Long companyId);

    /** Row lock on the service so concurrent orders can't both slip under maximumOrders. */
    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @org.springframework.data.jpa.repository.Query(
        "SELECT s FROM CompanyService s WHERE s.id = :id AND s.company.id = :companyId")
    Optional<CompanyService> findByIdAndCompanyIdForUpdate(
        @org.springframework.data.repository.query.Param("id") Long id,
        @org.springframework.data.repository.query.Param("companyId") Long companyId);

    boolean existsByCompanyIdAndNameAndIdNot(Long companyId, String name, Long excludeId);
}
