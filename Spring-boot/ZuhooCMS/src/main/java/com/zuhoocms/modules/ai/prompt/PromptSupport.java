package com.zuhoocms.modules.ai.prompt;

import com.zuhoocms.modules.ai.exception.AiPromptException;

/** Shared helpers for the *PromptBuilder classes, deliberately not a base class since the builders' fields and prompt shapes are unrelated. */
final class PromptSupport {

    private PromptSupport() {}

    static String orDefault(String value, String fallback) {
        return value != null && !value.isBlank() ? value : fallback;
    }

    static void requireNonBlank(String value, String fieldName, String featureName) {
        if (value == null || value.isBlank()) {
            throw new AiPromptException(fieldName + " is required for " + featureName + " prompt");
        }
    }
}
