package com.zuhoocms.modules.ai.provider;

import com.zuhoocms.modules.ai.client.AiToolCallOrText;
import com.zuhoocms.modules.ai.client.AiToolExchange;
import com.zuhoocms.modules.ai.enums.AiModel;
import com.zuhoocms.modules.ai.enums.AiProviderType;
import com.zuhoocms.modules.ai.tool.AiTool;

import java.util.List;

/**
 * Business abstraction over one AI provider.
 * Wraps an AiHttpClient with resolved credentials and model config.
 * AiProviderResolver builds the correct adapter at runtime.
 */
public interface AiProviderAdapter {

    String generate(String prompt);

    AiToolCallOrText callWithTools(String prompt, List<AiTool> tools, List<AiToolExchange> priorExchanges);

    AiProviderType getProviderType();

    AiModel getModel();
}
