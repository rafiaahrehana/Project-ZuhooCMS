package com.zuhoocms.modules.finance.fixedasset;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface FixedAssetRepository extends JpaRepository<FixedAsset, Long> {

    Optional<FixedAsset> findByIdAndCompanyId(Long id, Long companyId);

    Page<FixedAsset> findByCompanyId(Long companyId, Pageable pageable);

    List<FixedAsset> findByCompanyIdAndStatus(Long companyId, FixedAssetStatus status);

    // Cross-company: runs from a scheduler outside any HTTP request context, matching LicenseExpiryScheduler's convention.
    @org.springframework.data.jpa.repository.Query(
            "SELECT DISTINCT f.companyId FROM FixedAsset f WHERE f.status = :status")
    List<Long> findDistinctCompanyIdsByStatus(FixedAssetStatus status);
}
