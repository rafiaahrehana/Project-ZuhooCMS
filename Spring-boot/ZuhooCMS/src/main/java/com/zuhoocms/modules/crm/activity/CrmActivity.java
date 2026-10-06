package com.zuhoocms.modules.crm.activity;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.opportunity.Opportunity;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDateTime;


 // Unified timeline entry for clients and opportunities; lead-specific activities remain in LeadActivity.

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "crm_activities", indexes = {
    @Index(name = "idx_crm_activity_company", columnList = "company_id"),
    @Index(name = "idx_crm_activity_client", columnList = "client_id"),
    @Index(name = "idx_crm_activity_opportunity", columnList = "opportunity_id"),
    @Index(name = "idx_crm_activity_date", columnList = "activity_date")
})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CrmActivity extends BaseEntity {

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private CrmActivityType type;

    @Column(nullable = false, length = 200)
    private String subject;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(name = "activity_date", nullable = false)
    private LocalDateTime activityDate;

    private LocalDateTime scheduledAt;

    @Builder.Default
    @Column(nullable = false)
    private boolean completed = true;

    @Builder.Default
    @Column(nullable = false)
    private boolean systemGenerated = false;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "client_id")
    private Client client;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "opportunity_id")
    private Opportunity opportunity;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "lead_id")
    private Lead lead; // Optional: points to CRM Lead

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "performed_by_id")
    private User performedBy;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    private LocalDateTime followUpAt;

    @Builder.Default
    private boolean followUpDone = false;

    /**
     * When the due notification was sent, null until it has been; without it the scheduler re-notified every 30 minutes, 48 times a day per overdue item.
     *
     * No reschedule path exists yet; one must clear this, or the moved follow-up never notifies again.
     */
    private LocalDateTime followUpNotifiedAt;

    @PrePersist
    protected void onCreate() {
        if (this.activityDate == null) {
            this.activityDate = LocalDateTime.now();
        }
    }
}
