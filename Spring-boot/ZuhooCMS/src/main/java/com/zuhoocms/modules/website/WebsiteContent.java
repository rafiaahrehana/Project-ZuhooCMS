package com.zuhoocms.modules.website;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDateTime;

/** Published website content addressed by slug: {@link #type} picks the applicable fields - PAGE uses slug/title/body, POST also the excerpt/cover/author/publishedAt/category/readMinutes, left null for pages. */
@Entity
@Table(name = "website_content")
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class WebsiteContent extends BaseEntity {

    @Column(name = "company_id", nullable = false)
    private Long companyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ContentType type;

    // Unique per company, not globally: (company_id, slug) index created by WebsiteSlugIndexMigration.
    private String slug;
    private String title;
    // No @Lob: on PostgreSQL it maps a String to a large-object oid and reading a TEXT value fails with "Bad value for type long".
    @Column(columnDefinition = "TEXT")
    private String body;

    // POST-only fields
    @Column(length = 600)
    private String excerpt;
    private String coverImageUrl;
    private String author;
    private LocalDateTime publishedAt;
    private String category;
    private int readMinutes;

    /** Drafts are hidden from the public site; the column default keeps pre-existing rows published, and a future publishedAt stays hidden until then. */
    @Builder.Default
    @Column(nullable = false, columnDefinition = "boolean default true")
    private boolean published = true;
}
