package com.zuhoocms.modules.ai.client;

import com.zuhoocms.modules.ai.exception.AiProviderException;
import com.zuhoocms.modules.ai.tool.AiTool;
import lombok.RequiredArgsConstructor;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor

public class GeminiClient implements AiHttpClient {

    private static final String BASE_URL =
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent";

    @Qualifier("aiRestTemplate")
    private final RestTemplate aiRestTemplate;

    @Override
    public String call(String apiKey, String prompt, String model, double temperature, int maxTokens) {
        // Gemini 2.5 thinking spends reasoning tokens from the same maxOutputTokens budget, cutting the visible answer off mid-sentence, so disable it.
        // Models that reject thinkingConfig (1.5 family, 2.5 Pro) get one retry without it.
        try {
            return doCall(apiKey, prompt, model, temperature, maxTokens, true);
        } catch (HttpClientErrorException e) {
            // Google's rejection is a generic "Request contains an invalid argument." with no field name, so any 400 gets one retry without thinkingConfig.
            if (e.getStatusCode().value() == 400) {
                try {
                    // Thinking is on for this retry, so raise the budget to leave the answer room alongside its reasoning tokens.
                    return doCall(apiKey, prompt, model, temperature, Math.max(maxTokens, 8192), false);
                } catch (HttpClientErrorException retryFailure) {
                    throw new AiProviderException("Gemini API call failed: " + retryFailure.getMessage(), isRetryable(retryFailure));
                }
            }
            throw new AiProviderException("Gemini API call failed: " + e.getMessage(), isRetryable(e));
        }
    }

    private String doCall(String apiKey, String prompt, String model, double temperature, int maxTokens, boolean disableThinking) {
        String url = String.format(BASE_URL, model);

        Map<String, Object> generationConfig = new java.util.HashMap<>();
        generationConfig.put("temperature", temperature);
        generationConfig.put("maxOutputTokens", maxTokens);
        if (disableThinking) {
            generationConfig.put("thinkingConfig", Map.of("thinkingBudget", 0));
        }

        Map<String, Object> body = Map.of(
            "contents", List.of(Map.of("parts", List.of(Map.of("text", prompt)))),
            "generationConfig", generationConfig
        );

        try {
            Map<?, ?> response = post(url, apiKey, body);
            return extractText(response);
        } catch (AiProviderException | HttpClientErrorException e) {
            throw e;
        } catch (Exception e) {
            throw new AiProviderException("Gemini API call failed: " + e.getMessage(), isRetryable(e));
        }
    }


    /** Gemini 2.x splits one answer across multiple parts (thought parts flagged "thought": true): parts[0] alone silently truncated longer responses. */
    private String extractText(Map<?, ?> response) {
        try {
            List<?> candidates = (List<?>) response.get("candidates");
            Map<?, ?> first    = (Map<?, ?>) candidates.get(0);
            Map<?, ?> content  = (Map<?, ?>) first.get("content");
            List<?> parts      = (List<?>) content.get("parts");
            StringBuilder text = new StringBuilder();
            for (Object part : parts) {
                Map<?, ?> p = (Map<?, ?>) part;
                if (Boolean.TRUE.equals(p.get("thought"))) continue;
                Object t = p.get("text");
                if (t != null) text.append(t);
            }
            if (text.isEmpty()) {
                Object finishReason = first.get("finishReason");
                throw new AiProviderException("Gemini returned no text"
                        + (finishReason != null ? " (finishReason: " + finishReason + ")" : ""));
            }
            return text.toString();
        } catch (AiProviderException e) {
            throw e;
        } catch (Exception e) {
            throw new AiProviderException("Failed to parse Gemini response: " + e.getMessage());
        }
    }

    /** The key travels in the x-goog-api-key header, never the URL: a query-string key leaks into exception messages, proxy and access logs. */
    private Map<?, ?> post(String url, String apiKey, Map<String, Object> body) {
        org.springframework.http.HttpHeaders headers = new org.springframework.http.HttpHeaders();
        headers.setContentType(org.springframework.http.MediaType.APPLICATION_JSON);
        headers.set("x-goog-api-key", apiKey);
        return aiRestTemplate.exchange(url, org.springframework.http.HttpMethod.POST,
            new org.springframework.http.HttpEntity<>(body, headers), Map.class).getBody();
    }

    // Retry on timeouts/connection errors/5xx/429 - not on other 4xx (bad request, auth failure, etc).
    private boolean isRetryable(Exception e) {
        return AiRetryPolicy.isRetryable(e);
    }

    @Override
    public AiToolCallOrText callWithTools(String apiKey, String prompt, String model, double temperature, int maxTokens,
                                           List<AiTool> tools, List<AiToolExchange> priorExchanges) {
        String url = String.format(BASE_URL, model);

        List<Object> contents = new ArrayList<>();
        contents.add(Map.of("role", "user", "parts", List.of(Map.of("text", prompt))));
        for (AiToolExchange ex : priorExchanges) {
            contents.add(Map.of("role", "model", "parts",
                List.of(Map.of("functionCall", Map.of("name", ex.getToolName(), "args", ex.getToolArgs())))));
            contents.add(Map.of("role", "user", "parts",
                List.of(Map.of("functionResponse", Map.of("name", ex.getToolName(),
                    "response", Map.of("content", ex.getResultText()))))));
        }

        List<Map<String, Object>> declarations = tools.stream()
            .map(t -> {
                Map<String, Object> d = new java.util.HashMap<>();
                d.put("name", t.name());
                d.put("description", t.description());
                d.put("parameters", t.parametersSchema());
                return d;
            })
            .toList();

        Map<String, Object> body = new java.util.HashMap<>();
        body.put("contents", contents);
        // After a tool has run this turn, omit the declarations: the v1 loop cannot chain a second tool call.
        if (priorExchanges.isEmpty()) {
            body.put("tools", List.of(Map.of("functionDeclarations", declarations)));
        }
        body.put("generationConfig", Map.of("temperature", temperature, "maxOutputTokens", maxTokens));

        try {
            Map<?, ?> response = post(url, apiKey, body);
            return extractToolCallOrText(response);
        } catch (AiProviderException e) {
            throw e;
        } catch (Exception e) {
            throw new AiProviderException("Gemini tool-call failed: " + e.getMessage(), isRetryable(e));
        }
    }

    @SuppressWarnings("unchecked")
    private AiToolCallOrText extractToolCallOrText(Map<?, ?> response) {
        try {
            List<?> candidates = (List<?>) response.get("candidates");
            Map<?, ?> first    = (Map<?, ?>) candidates.get(0);
            Map<?, ?> content  = (Map<?, ?>) first.get("content");
            List<?> parts      = (List<?>) content.get("parts");

            StringBuilder text = new StringBuilder();
            for (Object part : parts) {
                Map<?, ?> p = (Map<?, ?>) part;
                if (p.get("functionCall") != null) {
                    Map<String, Object> fc = (Map<String, Object>) p.get("functionCall");
                    Map<String, Object> args = fc.get("args") != null
                        ? (Map<String, Object>) fc.get("args") : Map.of();
                    return AiToolCallOrText.toolCall((String) fc.get("name"), args, null);
                }
                if (Boolean.TRUE.equals(p.get("thought"))) continue;
                Object t = p.get("text");
                if (t != null) text.append(t);
            }
            return AiToolCallOrText.text(text.toString());
        } catch (Exception e) {
            throw new AiProviderException("Failed to parse Gemini tool-call response: " + e.getMessage());
        }
    }
}
