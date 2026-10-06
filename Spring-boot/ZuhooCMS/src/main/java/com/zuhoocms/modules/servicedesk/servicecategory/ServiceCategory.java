package com.zuhoocms.modules.servicedesk.servicecategory;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;

/** Categories are per-company, not a shared platform taxonomy, so name uniqueness is scoped to companyId rather than global. */
@Entity
@Table(name = "service_categories",
        uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "name"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class ServiceCategory extends BaseEntity {

    @Column(name = "company_id", nullable = false)
    private Long companyId;

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    private String iconUrl;

    @Builder.Default
    private boolean active = true;

    private String nameBn;
    private String descriptionBn;

    @Column(nullable = false)
    @Builder.Default
    private int sortOrder = 0;
}
