package com.zuhoocms.shared.storage;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoredFileRepository extends JpaRepository<StoredFile, Long> {

    /** Bytes a company currently stores (soft-deleted rows excluded by BaseEntity's restriction). */
    @Query("SELECT COALESCE(SUM(f.size), 0) FROM StoredFile f WHERE f.companyId = :companyId")
    long sumSizeByCompanyId(@Param("companyId") Long companyId);
}
