package com.zuhoocms.modules.ai.dto.request;

import com.zuhoocms.modules.ai.enums.AiFeature;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public class AiGenerateRequest {

    @NotNull(message = "Feature is required")
    private AiFeature feature;

    @NotBlank(message = "Prompt is required")
    @Size(max = 8000, message = "Prompt must be at most 8000 characters")
    private String prompt;

    // Optional: when set, generate() prepends the thread's prior messages and saves this exchange onto it; omitted, the call is stateless.
    private Long threadId;

    public AiFeature getFeature() { return feature; }
    public void setFeature(AiFeature feature) { this.feature = feature; }
    public String getPrompt() { return prompt; }
    public void setPrompt(String prompt) { this.prompt = prompt; }
    public Long getThreadId() { return threadId; }
    public void setThreadId(Long threadId) { this.threadId = threadId; }
}
