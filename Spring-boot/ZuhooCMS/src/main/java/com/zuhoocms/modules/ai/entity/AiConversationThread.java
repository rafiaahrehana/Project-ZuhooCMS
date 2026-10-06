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

/** Groups AiConversation messages into one resumable chat and carries the pending write-action; thread is a nullable FK on AiConversation so unthreaded generateRaw() callers still work. */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(
    name = "ai_conversation_threads",
    indexes = {
        @Index(name = "idx_ai_thread_company_user", columnList = "company_id, user_id"),
    }
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
public class AiConversationThread extends BaseEntity {

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private AiFeature feature;

    // First ~60 chars of the first message, set once, so the thread list is readable without re-fetching messages.
    @Column(length = 80)
    private String title;

    // JSON of {tool, args}, non-null only while a write-tool proposal awaits a yes/no; cleared after every agent turn however it ends.
    @Column(name = "pending_action", columnDefinition = "TEXT")
    private String pendingAction;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;
}
