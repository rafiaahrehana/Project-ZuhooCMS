package com.zuhoocms.modules.ai.entity;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

/** Every tool the agent executed, kept alongside AiConversation's text so "what did the AI do on my behalf" stays reviewable independent of the conversation. */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(
    name = "ai_tool_call_logs",
    indexes = {
        @Index(name = "idx_ai_tool_log_company_user", columnList = "company_id, user_id"),
        @Index(name = "idx_ai_tool_log_thread", columnList = "thread_id"),
    }
)
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
public class AiToolCallLog extends BaseEntity {

    @Column(name = "tool_name", nullable = false, length = 60)
    private String toolName;

    @Column(name = "tool_args", columnDefinition = "TEXT")
    private String toolArgs;

    @Column(nullable = false)
    private boolean success;

    @Column(columnDefinition = "TEXT")
    private String resultSummary;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "thread_id")
    private AiConversationThread thread;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;
}
