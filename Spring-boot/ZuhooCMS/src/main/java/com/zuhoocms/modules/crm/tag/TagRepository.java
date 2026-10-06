package com.zuhoocms.modules.crm.tag;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface TagRepository extends JpaRepository<Tag, Long> {

    List<Tag> findByCompanyIdOrderByNameAsc(Long companyId);

    Optional<Tag> findByIdAndCompanyId(Long id, Long companyId);

    /** Name collision check, excluding the row being edited (null on create); BaseEntity's @SQLRestriction scopes it to deleted = false, so a deleted tag's name is reusable - see the partial index in CrmSchemaMigrationRunner. */
    @Query("SELECT COUNT(t) > 0 FROM Tag t WHERE t.company.id = :companyId " +
           "AND LOWER(t.name) = LOWER(:name) AND (:excludeId IS NULL OR t.id <> :excludeId)")
    boolean existsByNameIgnoringCase(@Param("name") String name,
                                     @Param("companyId") Long companyId,
                                     @Param("excludeId") Long excludeId);

    List<Tag> findByIdInAndCompanyId(List<Long> ids, Long companyId);
}
