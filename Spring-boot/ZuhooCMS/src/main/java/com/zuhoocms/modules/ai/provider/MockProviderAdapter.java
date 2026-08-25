package com.zuhoocms.modules.ai.provider;

import com.zuhoocms.modules.ai.client.AiToolCallOrText;
import com.zuhoocms.modules.ai.client.AiToolExchange;
import com.zuhoocms.modules.ai.client.MockAiClient;
import com.zuhoocms.modules.ai.enums.AiModel;
import com.zuhoocms.modules.ai.enums.AiProviderType;
import com.zuhoocms.modules.ai.tool.AiTool;
import lombok.RequiredArgsConstructor;

import java.util.List;

@RequiredArgsConstructor
public class MockProviderAdapter implements AiProviderAdapter {

    private final MockAiClient client;

    @Override
    public String generate(String prompt) {
        return client.call(prompt, "mock", 0.0, 0);
    }

    @Override
    public AiToolCallOrText callWithTools(String prompt, List<AiTool> tools, List<AiToolExchange> priorExchanges) {
        return client.callWithTools(prompt, "mock", 0.0, 0, tools, priorExchanges);
    }

    @Override
    public AiProviderType getProviderType() {
        return AiProviderType.MOCK;
    }

    @Override
    public AiModel getModel() {
        return AiModel.GEMINI_2_5_FLASH;
    }
}
