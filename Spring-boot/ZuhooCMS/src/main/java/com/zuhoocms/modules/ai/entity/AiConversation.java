package com.zuhoocms.modules.ai.entity;

import com.zuhoocms.modules.ai.enums.AiFeature;
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
    name = "ai_conversations",
    indexes = {
        @Index(name = "idx_ai_conv_company",  columnList = "company_id"),
        @Index(name = "idx_ai_conv_feature",  columnList = "company_id, feature"),
        @Index(name = "idx_ai_conv_user",     columnList = "company_id, user_id")
    }
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
public class AiConversation extends BaseEntity {

    @Column(nullable = false, length = 36)
    private String conversationUuid;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private AiFeature feature;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private AiProviderType provider;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 25)
    private AiModel model;

    @Column(columnDefinition = "TEXT")
    private String requestPayload;

    @Column(columnDefinition = "TEXT")
    private String responsePayload;

    private Long executionTimeMs;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    // Nullable: set only when generate() was called with a threadId. requestPayload/responsePayload carry both sides of an exchange, so history replay needs no per-message role column.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "thread_id")
    private AiConversationThread thread;

    // Nullable only for rows written before this column existed; those are visible to AI_ADMIN only (see AiServiceImpl#listConversations).
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private com.zuhoocms.auth.user.User user;

}
