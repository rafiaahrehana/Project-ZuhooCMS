package com.zuhoocms.modules.ai.client;

import com.zuhoocms.modules.ai.tool.AiTool;

import java.util.List;

public interface AiHttpClient {

    /** {@code apiKey} is a parameter, never state on this singleton bean: a field would let one tenant's concurrent request overwrite another's key mid-flight. See AiProviderResolver. */
    String call(String apiKey, String prompt, String model, double temperature, int maxTokens);

    /** Like {@link #call}, but the model may invoke one of {@code tools}; {@code priorExchanges} is empty on the first call and carries the executed tool's result on the second. */
    AiToolCallOrText callWithTools(String apiKey, String prompt, String model, double temperature, int maxTokens,
                                    List<AiTool> tools, List<AiToolExchange> priorExchanges);
}
