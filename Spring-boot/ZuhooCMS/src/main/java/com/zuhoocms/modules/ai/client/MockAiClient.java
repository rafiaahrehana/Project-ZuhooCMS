package com.zuhoocms.modules.ai.client;


import com.fasterxml.jackson.databind.ObjectMapper;
import com.zuhoocms.modules.ai.config.AiProperties;
import com.zuhoocms.modules.ai.tool.AiTool;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Component
@RequiredArgsConstructor
public class MockAiClient implements AiHttpClient {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Dev/test directive, e.g. {@code [[tool:apply_leave {...}]]}, forcing a tool choice; the name is returned even when not offered, to exercise the agent loop's refusal path. */
    private static final Pattern TOOL_DIRECTIVE =
        Pattern.compile("\\[\\[tool:([a-z_]+)\\s*(\\{.*?\\})?\\s*\\]\\]", Pattern.DOTALL);

    private final AiProperties aiProperties;

    @Override
    public String call(String apiKey, String prompt, String model, double temperature, int maxTokens) {
        if (aiProperties.isMockEchoPrompt()) {
            return "[MOCK AI RESPONSE] Prompt received (" + prompt.length() + " chars):\n" + prompt;
        }
        return "[MOCK AI RESPONSE] Prompt received ("
            + prompt.length() + " chars). "
            + "Configure ai.default-provider=gemini to use a real provider.";
    }

    /** Simulates tool selection by keyword match so the agent loop runs without a provider key; never calls a tool twice in a turn. */
    @Override
    @SuppressWarnings("unchecked")
    public AiToolCallOrText callWithTools(String apiKey, String prompt, String model, double temperature, int maxTokens,
                                           List<AiTool> tools, List<AiToolExchange> priorExchanges) {
        if (!priorExchanges.isEmpty()) {
            AiToolExchange last = priorExchanges.get(priorExchanges.size() - 1);
            return AiToolCallOrText.text("[MOCK] " + last.getResultText());
        }

        // Only the latest user message counts, so earlier turns in the history cannot re-trigger a directive.
        String latest = latestUserMessage(prompt);
        Matcher m = TOOL_DIRECTIVE.matcher(latest);
        if (m.find()) {
            Map<String, Object> args = Map.of();
            if (m.group(2) != null) {
                try {
                    args = MAPPER.readValue(m.group(2), Map.class);
                } catch (Exception ignored) {
                    // Malformed test JSON - fall back to no arguments.
                }
            }
            return AiToolCallOrText.toolCall(m.group(1), args, "mock-call-1");
        }

        String lower = latest.toLowerCase();
        for (AiTool tool : tools) {
            String haystack = (tool.name() + " " + tool.description()).toLowerCase();
            for (String word : lower.split("\\W+")) {
                if (word.length() > 3 && haystack.contains(word)) {
                    return AiToolCallOrText.toolCall(tool.name(), Map.of(), "mock-call-1");
                }
            }
        }
        return AiToolCallOrText.text(call(apiKey, prompt, model, temperature, maxTokens));
    }

    private static String latestUserMessage(String prompt) {
        int idx = prompt.lastIndexOf("User: ");
        return idx >= 0 ? prompt.substring(idx + "User: ".length()) : prompt;
    }
}
