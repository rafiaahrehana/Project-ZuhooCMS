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

/** A person shown on the public website: {@link #type} picks the applicable fields - TEAM_MEMBER uses bio/photoUrl/email, TESTIMONIAL company/quote/avatarUrl/rating, the other side left null. */
@Entity
@Table(name = "website_people")
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class WebsitePerson extends BaseEntity {

    @Column(name = "company_id", nullable = false)
    private Long companyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private PersonType type;

    private String name;
    private String role;

    // TEAM_MEMBER fields
    // No @Lob: on PostgreSQL it maps a String to a large-object oid and reading a TEXT value fails with "Bad value for type long".
    @Column(columnDefinition = "TEXT")
    private String bio;
    private String photoUrl;
    private String email;

    // TESTIMONIAL fields
    private String company;
    // No @Lob: on PostgreSQL it maps a String to a large-object oid and reading a TEXT value fails with "Bad value for type long".
    @Column(columnDefinition = "TEXT")
    private String quote;
    private String avatarUrl;
    private int rating;

    /** The site's TeamMember model has socialLinks; none are stored per person yet, so always an empty list. */
    public java.util.List<SocialLink> getSocialLinks() {
        return java.util.List.of();
    }
}
