package com.zuhoocms.modules.finance.fixedasset;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface DepreciationRunRepository extends JpaRepository<DepreciationRun, Long> {

    boolean existsByCompanyIdAndYearAndMonth(Long companyId, int year, int month);

    List<DepreciationRun> findByCompanyIdOrderByYearDescMonthDesc(Long companyId);

    Optional<DepreciationRun> findByIdAndCompanyId(Long id, Long companyId);

    /** The most recently depreciated month: runs must go in calendar order, since skipping or repeating a month understates or double-counts accumulated depreciation and the per-month uniqueness constraint cannot catch it. */
    Optional<DepreciationRun> findFirstByCompanyIdOrderByYearDescMonthDesc(Long companyId);
}
