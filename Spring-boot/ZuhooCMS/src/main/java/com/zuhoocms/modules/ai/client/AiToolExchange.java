package com.zuhoocms.modules.ai.client;

import lombok.AllArgsConstructor;
import lombok.Getter;

import java.util.Map;

/** One called-tool-and-its-result pair, fed back into a follow-up callWithTools() so the provider can answer from the real result. */
@Getter
@AllArgsConstructor
public class AiToolExchange {
    private final String toolName;
    private final Map<String, Object> toolArgs;
    private final String callId;
    private final String resultText;
}
