package com.zuhoocms.modules.servicedesk.kb;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface KbArticleRepository extends JpaRepository<KbArticle, Long> {

    Optional<KbArticle> findByIdAndCompanyId(Long id, Long companyId);

    // clientOnly=true forces PUBLISHED + clientVisible, so a client cannot reach drafts/archived by passing a status filter.
    // The :keyword casts are required: used only inside CONCAT(), a NULL bind fails with "could not determine data type of parameter" before the IS NULL short-circuit.
    @Query("""
        SELECT a FROM KbArticle a
        WHERE a.companyId = :companyId
        AND (:keyword IS NULL OR LOWER(a.title) LIKE LOWER(CONCAT('%', CAST(:keyword AS string), '%'))
               OR LOWER(a.keywords) LIKE LOWER(CONCAT('%', CAST(:keyword AS string), '%')))
        AND (
            (:clientOnly = true AND a.status = com.zuhoocms.modules.servicedesk.kb.KbArticleStatus.PUBLISHED AND a.clientVisible = true)
            OR
            (:clientOnly = false AND (:status IS NULL OR a.status = :status))
        )
        """)
    Page<KbArticle> search(
        @Param("companyId") Long companyId,
        @Param("keyword") String keyword,
        @Param("status") KbArticleStatus status,
        @Param("clientOnly") boolean clientOnly,
        Pageable pageable
    );
}
