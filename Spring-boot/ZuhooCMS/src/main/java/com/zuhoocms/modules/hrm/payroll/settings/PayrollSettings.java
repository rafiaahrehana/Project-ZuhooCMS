package com.zuhoocms.modules.hrm.payroll.settings;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.enums.PerDayBasis;
import com.zuhoocms.enums.SalaryBase;
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

/**
 * One company's payroll policy: per-day basis, absence cost, overtime and default salary component split.
 * Its own table rather than columns on Company: HR policy, not company identity, and it carries its own permission.
 * Every default reproduces the previously hardcoded behaviour, so an existing tenant's payroll is unchanged until an owner edits it.
 */
@Entity
@Table(name = "payroll_settings")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PayrollSettings extends BaseEntity {

    /** One row per company. */
    @Column(nullable = false, unique = true)
    private Long companyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private PerDayBasis perDayBasis = PerDayBasis.CALENDAR_DAYS;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private SalaryBase absenceDeductionBase = SalaryBase.GROSS;

    /** Off by default: salaried staff take time off in lieu; shift-based tenants turn it on. */
    @Builder.Default
    private boolean overtimeEnabled = false;

    /** Premium on the ordinary hourly rate; defaults to 2.00 per Bangladesh Labour Act 2006 s.108, lowerable by tenants under other rules. */
    @Column(precision = 4, scale = 2)
    @Builder.Default
    private BigDecimal overtimeMultiplier = new BigDecimal("2.00");

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private SalaryBase overtimeBase = SalaryBase.BASIC;

    /** Hours in a standard working day, used to turn a day rate into an hourly rate. */
    @Column(precision = 4, scale = 2)
    @Builder.Default
    private BigDecimal standardHoursPerDay = new BigDecimal("8.00");

    // Percentages OF BASIC that pre-fill a new salary structure; SalaryStructure stores the real per-employee amounts, so grades may differ.

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal houseRentPercent = new BigDecimal("40.00");

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal medicalPercent = new BigDecimal("10.00");

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal transportPercent = new BigDecimal("10.00");

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal foodPercent = BigDecimal.ZERO;

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal providentFundPercent = new BigDecimal("10.00");

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal taxPercent = new BigDecimal("5.00");
}
