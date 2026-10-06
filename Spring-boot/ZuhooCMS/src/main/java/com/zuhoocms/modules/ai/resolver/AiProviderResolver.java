package com.zuhoocms.modules.ai.resolver;

import com.zuhoocms.modules.ai.client.ClaudeClient;
import com.zuhoocms.modules.ai.client.GeminiClient;
import com.zuhoocms.modules.ai.client.GroqClient;
import com.zuhoocms.modules.ai.client.MockAiClient;
import com.zuhoocms.modules.ai.client.OpenAiClient;
import com.zuhoocms.modules.ai.config.AiProperties;
import com.zuhoocms.modules.ai.entity.AiProviderConfig;
import com.zuhoocms.modules.ai.provider.*;
import com.zuhoocms.modules.ai.repository.AiProviderConfigRepository;
import com.zuhoocms.modules.ai.util.AiKeyDecryptor;
import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Component;

import java.util.Optional;

@Component
@RequiredArgsConstructor

public class AiProviderResolver {

    private final AiProviderConfigRepository configRepository;
    private final AiProperties aiProperties;
    private final GeminiClient geminiClient;
    private final ClaudeClient claudeClient;
    private final OpenAiClient openAiClient;
    private final GroqClient groqClient;
    private final MockAiClient mockAiClient;
    private final AiKeyDecryptor keyDecryptor;

    public AiProviderAdapter resolve(Long companyId) {
        // ai.force-mock (default false): guarantees no real provider is called, whatever is saved in ai_provider_configs.
        if (aiProperties.isForceMock()) {
            return new MockProviderAdapter(mockAiClient);
        }
        if (companyId != null) {
            Optional<AiProviderConfig> config =
                configRepository.findByCompanyIdAndActiveTrue(companyId);
            if (config.isPresent()) {
                return buildFromConfig(config.get());
            }
        }

        // Fallback to global platform configuration in database (companyId = null)
        Optional<AiProviderConfig> globalConfig =
            configRepository.findByCompanyIdAndActiveTrue(null);
        if (globalConfig.isPresent()) {
            return buildFromConfig(globalConfig.get());
        }

        return buildFromDefaults();
    }

    public AiProviderAdapter resolveDefault() {
        return buildFromDefaults();
    }

    private AiProviderAdapter buildFromConfig(AiProviderConfig config) {
        String apiKey = resolveApiKey(config);
        double temp   = config.getTemperature() != null
            ? config.getTemperature().doubleValue() : 0.7;
        // Null would NPE on unboxing, and a small saved value starves Gemini 2.x thinking models, whose reasoning tokens share the output budget.
        Integer configured = config.getMaxTokens();
        int maxTokens = (configured == null || configured < 1024) ? 2048 : configured;

        // The key travels straight into the adapter, never onto the singleton client bean - see AiHttpClient.call for the cross-tenant key leak that caused.
        return switch (config.getAiProviderType()) {
            case GEMINI -> new GeminiProviderAdapter(geminiClient, apiKey, config.getAiModel(), temp, maxTokens);
            case CLAUDE -> new ClaudeProviderAdapter(claudeClient, apiKey, config.getAiModel(), temp, maxTokens);
            case OPENAI -> new OpenAiProviderAdapter(openAiClient, apiKey, config.getAiModel(), temp, maxTokens);
            case GROQ -> new GroqProviderAdapter(groqClient, apiKey, config.getAiModel(), temp, maxTokens);
            case MOCK -> new MockProviderAdapter(mockAiClient);
        };
    }

    private AiProviderAdapter buildFromDefaults() {
        if (aiProperties.isForceMock()) {
            return new MockProviderAdapter(mockAiClient);
        }
        return switch (aiProperties.getDefaultProvider()) {
            case GEMINI -> new GeminiProviderAdapter(
                    geminiClient,
                    aiProperties.getGemini().getApiKey(),
                    aiProperties.getDefaultModel(),
                    aiProperties.getGemini().getTemperature(),
                    aiProperties.getGemini().getMaxTokens()
                );
            case CLAUDE -> new ClaudeProviderAdapter(
                    claudeClient,
                    aiProperties.getClaude().getApiKey(),
                    aiProperties.getDefaultModel(),
                    aiProperties.getClaude().getTemperature(),
                    aiProperties.getClaude().getMaxTokens()
                );
            case OPENAI -> new OpenAiProviderAdapter(
                    openAiClient,
                    aiProperties.getOpenai().getApiKey(),
                    aiProperties.getDefaultModel(),
                    aiProperties.getOpenai().getTemperature(),
                    aiProperties.getOpenai().getMaxTokens()
                );
            case GROQ -> new GroqProviderAdapter(
                    groqClient,
                    aiProperties.getGroq().getApiKey(),
                    aiProperties.getDefaultModel(),
                    aiProperties.getGroq().getTemperature(),
                    aiProperties.getGroq().getMaxTokens()
                );
            case MOCK -> new MockProviderAdapter(mockAiClient);
        };
    }

    private String resolveApiKey(AiProviderConfig config) {
        if (config.getApiKeyEncrypted() != null)
            return keyDecryptor.decrypt(config.getApiKeyEncrypted());

        return switch (config.getAiProviderType()) {
            case GEMINI -> aiProperties.getGemini().getApiKey();
            case CLAUDE -> aiProperties.getClaude().getApiKey();
            case OPENAI -> aiProperties.getOpenai().getApiKey();
            case GROQ   -> aiProperties.getGroq().getApiKey();
            case MOCK   -> "mock";
        };
    }
}
