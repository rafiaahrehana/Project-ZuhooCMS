package com.zuhoocms.modules.crm.tag;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

/** A shared tag taxonomy across Lead/Opportunity/Client within one company, not free text per record (Client.tags remains a legacy free-text field). */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
/*
 * No @UniqueConstraint on purpose: JPA's total (company_id, name) constraint covered soft-deleted rows, reserving a deleted tag's name, and was case-sensitive while the service checks existsByNameIgnoreCase.
 * CrmSchemaMigrationRunner creates the replacement instead: UNIQUE (company_id, lower(name)) WHERE deleted = false.
 */
@Table(name = "tags")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Tag extends BaseEntity {

    @Column(nullable = false, length = 60)
    private String name;

    // Hex color for the chip, e.g. "#8352ED"
    @Column(nullable = false, length = 20)
    private String color;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;
}
