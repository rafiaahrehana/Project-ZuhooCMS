package com.zuhoocms.modules.ai.dto.response;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.enums.AiModel;
import com.zuhoocms.modules.ai.enums.AiProviderType;

public class AiGenerateResponse {
    private String conversationUuid;
    private AiFeature feature;
    private AiProviderType provider;
    private AiModel model;
    private String result;
    private long executionTimeMs;
    private Long threadId;
    // True when `result` is a write-action proposal awaiting confirmation; the frontend renders it as a confirm/cancel card instead of a chat bubble.
    private boolean awaitingConfirmation;
    // The user's own message for this exchange, set only when replaying a thread's history (see AiServiceImpl#getThreadMessages);
    // without it the chat replays assistant-side only. Null on a live generate(), where the client already has the text it just sent.
    private String requestPayload;

    public String getConversationUuid() { return conversationUuid; }
    public void setConversationUuid(String conversationUuid) { this.conversationUuid = conversationUuid; }
    public AiFeature getFeature() { return feature; }
    public void setFeature(AiFeature feature) { this.feature = feature; }
    public AiProviderType getProvider() { return provider; }
    public void setProvider(AiProviderType provider) { this.provider = provider; }
    public AiModel getModel() { return model; }
    public void setModel(AiModel model) { this.model = model; }
    public String getResult() { return result; }
    public void setResult(String result) { this.result = result; }
    public long getExecutionTimeMs() { return executionTimeMs; }
    public void setExecutionTimeMs(long executionTimeMs) { this.executionTimeMs = executionTimeMs; }
    public Long getThreadId() { return threadId; }
    public void setThreadId(Long threadId) { this.threadId = threadId; }
    public boolean isAwaitingConfirmation() { return awaitingConfirmation; }
    public void setAwaitingConfirmation(boolean awaitingConfirmation) { this.awaitingConfirmation = awaitingConfirmation; }
    public String getRequestPayload() { return requestPayload; }
    public void setRequestPayload(String requestPayload) { this.requestPayload = requestPayload; }
}
