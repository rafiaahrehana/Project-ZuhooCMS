package com.zuhoocms.modules.ai.entity;

import com.zuhoocms.modules.ai.enums.AiModel;
import com.zuhoocms.modules.ai.enums.AiProviderType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(
    name = "ai_provider_configs",
    uniqueConstraints = {
        @UniqueConstraint(name = "uq_ai_config_company_provider",
            columnNames = {"company_id", "provider"})
    },
    indexes = {
        @Index(name = "idx_ai_config_company", columnList = "company_id"),
        @Index(name = "idx_ai_config_active",  columnList = "company_id, active")
    }
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
// The filter is widened to keep company_id IS NULL rows (the platform-wide fallback) visible: a plain "company_id = :companyId" hid them, so that step of AiProviderResolver's cascade never matched.
// Queries that must stay tenant-only constrain company_id themselves, so widening leaks nothing.
@Filter(name = "tenantFilter", condition = "(company_id = :companyId or company_id is null)")
public class AiProviderConfig extends BaseEntity {

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private AiProviderType aiProviderType;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 25)
    private AiModel aiModel;

    @Column(name = "api_key_encrypted", length = 512)
    private String apiKeyEncrypted;

    @Column(columnDefinition = "numeric(3,2)")
    private Double temperature;

    private Integer maxTokens;

    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    // Nullable: a row with no company is the platform-wide default, used as a fallback by AiProviderResolver.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id")
    private Company company;

}
