package com.zuhoocms.modules.finance.period;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDate;
import java.time.LocalDateTime;

/** A monthly accounting period within a fiscal year: closing a reviewed month stops anything being backdated into it, which otherwise silently changes financials already reported to stakeholders. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "accounting_periods",
    uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "fiscal_year", "period_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class AccountingPeriod extends BaseEntity {

    private Long companyId;

    private int fiscalYear;
    private int periodNumber; // 1-12, sequential within the fiscal year (not the calendar month)

    private LocalDate startDate;
    private LocalDate endDate;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 20)
    private PeriodStatus status = PeriodStatus.OPEN;

    private String closedBy;
    private LocalDateTime closedAt;

    private String reopenedBy;
    private LocalDateTime reopenedAt;

    public boolean covers(LocalDate date) {
        return !date.isBefore(startDate) && !date.isAfter(endDate);
    }
}
