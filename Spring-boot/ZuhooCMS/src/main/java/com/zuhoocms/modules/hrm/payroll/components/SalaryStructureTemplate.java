package com.zuhoocms.modules.hrm.payroll.components;

import com.zuhoocms.core.base.BaseEntity;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;

/** Reusable named salary recipe: basic as % of gross, HRA as % of basic, fixed allowances, remainder to special. Applying it stamps numbers onto the employee's own SalaryStructure; the template is untouched. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "salary_structure_templates")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SalaryStructureTemplate extends BaseEntity {

    @JsonIgnore
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @Column(nullable = false, length = 100)
    private String structureName;

    /** The grade's standard package; selecting the template fills Gross from here and everything else derives from it. */
    @Column(precision = 12, scale = 2)
    private BigDecimal defaultGross;

    /** % of gross. */
    @Builder.Default
    @Column(precision = 5, scale = 2)
    private BigDecimal basicPercentage = new BigDecimal("50");

    /** % of basic. */
    @Builder.Default
    @Column(precision = 5, scale = 2)
    private BigDecimal hraPercentage = new BigDecimal("40");

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal medicalAmount = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal transportAmount = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal internetAmount = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal mobileAmount = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal mealAmount = BigDecimal.ZERO;

    @Builder.Default
    private Boolean active = Boolean.TRUE;
}
