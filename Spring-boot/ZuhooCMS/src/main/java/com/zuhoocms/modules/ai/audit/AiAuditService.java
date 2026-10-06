package com.zuhoocms.modules.ai.audit;

import com.zuhoocms.modules.ai.entity.AiConversation;
import com.zuhoocms.modules.ai.entity.AiConversationThread;
import com.zuhoocms.modules.ai.entity.AiUsageLog;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.enums.AiModel;
import com.zuhoocms.modules.ai.enums.AiProviderType;
import com.zuhoocms.modules.ai.repository.AiConversationRepository;
import com.zuhoocms.modules.ai.repository.AiUsageLogRepository;
import com.zuhoocms.modules.ai.util.AiTokenCounter;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * {@link #recordUsage}: one ai_usage_logs row per provider call, sized from the prompt actually sent and written for failed calls too, so reports match what the provider saw.
 * {@link #recordConversation}: one ai_conversations row per user-visible exchange, with no usage row - a confirm/cancel reply makes no provider call.
 * Both run REQUIRES_NEW so an audit write never joins, or is rolled back with, a caller's business transaction.
 */
@Service
@RequiredArgsConstructor
public class AiAuditService {

    private final AiConversationRepository conversationRepository;
    private final AiUsageLogRepository usageLogRepository;
    private final AiTokenCounter tokenCounter;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordUsage(AiFeature feature, AiProviderType provider, AiModel model,
                            String promptSent, String response, long executionTimeMs,
                            User user, Company company) {
        usageLogRepository.save(AiUsageLog.builder()
            .aiFeature(feature)
            .provider(provider)
            .model(model)
            .inputTokens(tokenCounter.estimate(promptSent))
            .outputTokens(tokenCounter.estimate(response))
            .executionTimeMs(executionTimeMs)
            .logDate(LocalDate.now())
            .createdAt(LocalDateTime.now())
            .user(user)
            .company(company)
            .build());
    }

    /** Returns the new conversation's UUID. {@code thread} may be null (stateless call). */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public String recordConversation(AiFeature feature, AiProviderType provider, AiModel model,
                                     String requestPayload, String response, long executionTimeMs,
                                     User user, Company company, AiConversationThread thread) {
        String uuid = UUID.randomUUID().toString();
        conversationRepository.save(AiConversation.builder()
            .conversationUuid(uuid)
            .feature(feature)
            .provider(provider)
            .model(model)
            .requestPayload(requestPayload)
            .responsePayload(response)
            .executionTimeMs(executionTimeMs)
            .company(company)
            .user(user)
            .thread(thread)
            .build());
        return uuid;
    }
}
