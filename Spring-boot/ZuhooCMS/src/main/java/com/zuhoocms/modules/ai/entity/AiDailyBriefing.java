package com.zuhoocms.modules.ai.entity;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDate;

/** One cached briefing per (company, user, date), built lazily on first open so no AI generation is paid for on a day the app is never opened. */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(
    name = "ai_daily_briefings",
    uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "user_id", "briefing_date"})
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
public class AiDailyBriefing extends BaseEntity {

    @Column(name = "briefing_date", nullable = false)
    private LocalDate briefingDate;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;
}
