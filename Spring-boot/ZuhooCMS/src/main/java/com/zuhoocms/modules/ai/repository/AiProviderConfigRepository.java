package com.zuhoocms.modules.ai.repository;

import com.zuhoocms.modules.ai.entity.AiProviderConfig;
import com.zuhoocms.modules.ai.enums.AiProviderType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface AiProviderConfigRepository extends JpaRepository<AiProviderConfig, Long> {

    Optional<AiProviderConfig> findByCompanyIdAndActiveTrue(Long companyId);

    // Upsert lookup for uq_ai_config_company_provider: re-saving a provider updates its row instead of colliding with the unique constraint.
    Optional<AiProviderConfig> findByCompanyIdAndAiProviderType(Long companyId, AiProviderType aiProviderType);

    List<AiProviderConfig> findByCompanyIdOrderByAiProviderType(Long companyId);
}
