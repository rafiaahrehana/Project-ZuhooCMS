package com.zuhoocms.modules.crm.opportunity;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.enums.LeadSource;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.contact.ClientContact;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "opportunities", indexes = {
    @Index(name = "idx_opp_company_stage", columnList = "company_id,stage"),
    @Index(name = "idx_opp_client", columnList = "client_id"),
    @Index(name = "idx_opp_owner", columnList = "owner_id"),
    @Index(name = "idx_opp_close_date", columnList = "expected_close_date"),
    @Index(name = "idx_opp_created_at", columnList = "created_at")
})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Opportunity extends BaseEntity {

    @Column(nullable = false, length = 200)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    @Builder.Default
    private OpportunityStage stage = OpportunityStage.QUALIFICATION;

    @Enumerated(EnumType.STRING)
    @Column(length = 30)
    @Builder.Default
    private LeadSource source = LeadSource.OTHER;

    @Column(precision = 14, scale = 2)
    private BigDecimal amount;

    // 0 - 100, defaults from stage, overridable per deal
    @Column(nullable = false)
    @Builder.Default
    private Integer probability = OpportunityStage.QUALIFICATION.getDefaultProbability();

    @Column(name = "expected_close_date")
    private LocalDate expectedCloseDate;

    private LocalDate actualCloseDate;

    @Column(length = 255)
    private String nextStep;

    @Column(length = 255)
    private String lostReason;

    // The aggregatable why, with lostReason above as free-text detail; nullable because rows closed before the picklist existed have only text.
    @Enumerated(EnumType.STRING)
    @Column(length = 40)
    private com.zuhoocms.enums.LostReason lostReasonCode;

    private LocalDateTime lastActivityAt;
    private LocalDateTime stageChangedAt;

    // Set when CrmFollowUpScheduler notifies the owner, reset to null on new activity, so the next staleness period notifies again.
    private LocalDateTime staleNotifiedAt;

    // The account this deal belongs to; null until the deal is Won and a Client is created or linked.
    @ManyToOne(fetch = FetchType.LAZY, optional = true)
    @JoinColumn(name = "client_id", nullable = true)
    private Client client;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "contact_id")
    private ClientContact contact;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "source_lead_id")
    private Lead sourceLead;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "owner_id")
    private Employee owner;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(name = "opportunity_tags",
        joinColumns = @JoinColumn(name = "opportunity_id"),
        inverseJoinColumns = @JoinColumn(name = "tag_id"))
    @Builder.Default
    private java.util.List<com.zuhoocms.modules.crm.tag.Tag> tags = new java.util.ArrayList<>();

    @PrePersist
    protected void onCreate() {
        if (this.stage == null) {
            this.stage = OpportunityStage.QUALIFICATION;
        }
        if (this.probability == null) {
            this.probability = this.stage.getDefaultProbability();
        }
        if (this.stageChangedAt == null) {
            this.stageChangedAt = LocalDateTime.now();
        }
    }
}
