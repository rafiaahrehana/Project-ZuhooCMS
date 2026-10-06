package com.zuhoocms.modules.finance.vendor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface VendorRepository extends JpaRepository<Vendor, Long> {

    Optional<Vendor> findByIdAndCompanyId(Long id, Long companyId);

    Page<Vendor> findByCompanyId(Long companyId, Pageable pageable);

    Page<Vendor> findByCompanyIdAndNameContainingIgnoreCase(Long companyId, String name, Pageable pageable);

    List<Vendor> findByCompanyIdAndActiveTrueOrderByNameAsc(Long companyId);

    boolean existsByCompanyIdAndNameIgnoreCase(Long companyId, String name);

    /** Duplicate-name check ignoring the vendor being edited, so update() can run it on rename: otherwise a rename hit the (company_id, name) unique constraint as a raw 409, or slipped through once one row was soft-deleted. */
    boolean existsByCompanyIdAndNameIgnoreCaseAndIdNot(Long companyId, String name, Long id);
}
