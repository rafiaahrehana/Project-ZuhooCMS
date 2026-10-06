package com.zuhoocms.modules.ai.repository;


import com.zuhoocms.modules.ai.entity.AiConversation;
import com.zuhoocms.modules.ai.enums.AiFeature;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AiConversationRepository extends JpaRepository<AiConversation, Long> {

    // Company-wide history - AI_ADMIN only (AiServiceImpl#listConversations).
    Page<AiConversation> findByCompanyIdOrderByCreatedAtDesc(Long companyId, Pageable pageable);

    Page<AiConversation> findByCompanyIdAndFeatureOrderByCreatedAtDesc(
            Long companyId, AiFeature feature, Pageable pageable);

    // The caller's own history - everyone else.
    Page<AiConversation> findByCompanyIdAndUserIdOrderByCreatedAtDesc(
            Long companyId, Long userId, Pageable pageable);

    Page<AiConversation> findByCompanyIdAndUserIdAndFeatureOrderByCreatedAtDesc(
            Long companyId, Long userId, AiFeature feature, Pageable pageable);

    // Oldest-first, for rendering a thread's transcript page by page.
    org.springframework.data.domain.Page<AiConversation> findByThreadIdOrderByCreatedAtAsc(
            Long threadId, Pageable pageable);

    // Newest-first for prompt history: the model needs the latest N exchanges, which an ascending page would never reach on a long thread.
    java.util.List<AiConversation> findByThreadIdOrderByCreatedAtDescIdDesc(
            Long threadId, Pageable pageable);
}
