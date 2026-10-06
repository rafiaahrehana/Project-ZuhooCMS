package com.zuhoocms.modules.support.category;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface SupportCategoryRepository extends JpaRepository<SupportCategory, Long> {

    /** Live categories only (BaseEntity's @SQLRestriction hides soft-deleted rows). */
    Optional<SupportCategory> findByCategoryName(String name);

    boolean existsByCategoryNameIgnoreCaseAndIdNot(String name, Long id);

    boolean existsByCategoryNameIgnoreCase(String name);

    Page<SupportCategory> findByActive(boolean active, Pageable pageable);

    java.util.List<SupportCategory> findByActiveTrue();

    /** Frees a name still held by a legacy soft-deleted category: category_name keeps its unique constraint under ddl-auto=update, and native SQL is needed because @SQLRestriction hides these rows. */
    @Modifying
    @Query(value = "UPDATE support_categories SET category_name = LEFT(category_name, 200) || '#deleted-' || id "
            + "WHERE deleted = true AND category_name = :name", nativeQuery = true)
    int releaseNameFromDeleted(@Param("name") String name);
}
