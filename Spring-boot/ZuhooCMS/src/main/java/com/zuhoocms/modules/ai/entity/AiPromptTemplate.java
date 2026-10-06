package com.zuhoocms.modules.ai.entity;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

@Entity
@Table(
    name = "ai_prompt_templates",
    indexes = {
        @Index(name = "idx_ai_tpl_company", columnList = "company_id"),
        @Index(name = "idx_ai_tpl_feature", columnList = "feature, active")
    }
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
// As in AiProviderConfig, a company_id IS NULL row is a shared platform default: a strict "company_id = :companyId" filter dropped the IS NULL branch findActiveForFeature relies on, making those defaults unreachable.
@Filter(name = "tenantFilter", condition = "(company_id = :companyId or company_id is null)")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class AiPromptTemplate extends BaseEntity {

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private AiFeature feature;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String template;

    @Column(nullable = false)
    @Builder.Default
    private int version = 1;

    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    @Column(name = "change_notes", length = 500)
    private String changeNotes;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id")
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "updated_by_id")
    private User updatedBy;
}
