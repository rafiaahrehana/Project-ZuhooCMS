package com.zuhoocms.modules.ai.client;

import lombok.Getter;

import java.util.Map;

/** Either the provider replied with plain text, or it wants to call one tool. */
@Getter
public class AiToolCallOrText {

    private final String text;
    private final String toolName;
    private final Map<String, Object> toolArgs;
    // Provider-native call id (Claude tool_use.id, OpenAI/Groq tool_calls[].id; null for Gemini/Mock) - callWithTools() must hand it back unchanged on the follow-up call.
    private final String callId;

    private AiToolCallOrText(String text, String toolName, Map<String, Object> toolArgs, String callId) {
        this.text = text;
        this.toolName = toolName;
        this.toolArgs = toolArgs;
        this.callId = callId;
    }

    public static AiToolCallOrText text(String text) {
        return new AiToolCallOrText(text, null, null, null);
    }

    public static AiToolCallOrText toolCall(String toolName, Map<String, Object> args, String callId) {
        return new AiToolCallOrText(null, toolName, args, callId);
    }

    public boolean isToolCall() {
        return toolName != null;
    }
}
