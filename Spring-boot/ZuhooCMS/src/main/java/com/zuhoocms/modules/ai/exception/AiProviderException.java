package com.zuhoocms.modules.ai.exception;

import com.zuhoocms.shared.exception.ApiException;
import org.springframework.http.HttpStatus;

/** The message carries provider detail for the server log only: AiServiceImpl and GlobalExceptionHandler replace it with {@link #USER_MESSAGE} before it reaches a client. */
public class AiProviderException extends ApiException {

    /** The only text a client ever sees for a provider failure. */
    public static final String USER_MESSAGE =
        "The AI assistant is temporarily unavailable. Please try again in a moment.";

    private final boolean retryable;

    /** Non-retryable by default: parse failures and SAFETY / MAX_TOKENS finishes fail identically on a second attempt; transport code passes true for 429, 5xx and timeouts. */
    public AiProviderException(String message) {
        this(message, false);
    }

    public AiProviderException(String message, boolean retryable) {
        super(message, HttpStatus.SERVICE_UNAVAILABLE);
        this.retryable = retryable;
    }

    public boolean isRetryable() {
        return retryable;
    }
}
