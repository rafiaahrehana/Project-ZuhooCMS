package com.zuhoocms.modules.ai.util;

import org.springframework.stereotype.Component;


/**
 * Strips control characters other than tab/newline/carriage-return, which providers reject inside a JSON string body, and trims whitespace.
 * Deliberately does NOT escape backslashes or quotes: Jackson already does, and doing it here too double-escaped backslashes and turned quotes into apostrophes.
 */
@Component
public class AiTextSanitizer {

    private static final String ILLEGAL_CONTROL_CHARS = "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]";

    public String sanitize(String input) {
        if (input == null)
            return "";
        return input
            .replaceAll(ILLEGAL_CONTROL_CHARS, "")
            .trim();
    }
}
