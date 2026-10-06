package com.zuhoocms.modules.website;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface WebsiteContentRepository extends JpaRepository<WebsiteContent, Long> {
    Optional<WebsiteContent> findBySlugAndCompanyIdAndType(String slug, Long companyId, ContentType type);
    List<WebsiteContent> findByCompanyIdAndTypeOrderByPublishedAtDesc(Long companyId, ContentType type);
    List<WebsiteContent> findByCompanyIdAndTypeAndCategoryIgnoreCase(Long companyId, ContentType type, String category);

    /** Admin listing (blog posts or pages) - not filtered/sorted for public display. */
    List<WebsiteContent> findByCompanyIdAndType(Long companyId, ContentType type);

    @Query("""
        SELECT c FROM WebsiteContent c
        WHERE c.companyId = :companyId AND c.type = :type AND c.published = true
          AND (c.publishedAt IS NULL OR c.publishedAt <= :now)
          AND (:category = '' OR LOWER(c.category) = LOWER(:category))
        ORDER BY c.publishedAt DESC NULLS LAST, c.id DESC
        """)
    List<WebsiteContent> findPublic(@Param("companyId") Long companyId, @Param("type") ContentType type,
                                    @Param("category") String category, @Param("now") LocalDateTime now);

    @Query("""
        SELECT c FROM WebsiteContent c
        WHERE c.companyId = :companyId AND c.type = :type AND c.slug = :slug AND c.published = true
          AND (c.publishedAt IS NULL OR c.publishedAt <= :now)
        """)
    Optional<WebsiteContent> findPublicBySlug(@Param("companyId") Long companyId, @Param("type") ContentType type,
                                              @Param("slug") String slug, @Param("now") LocalDateTime now);
}
