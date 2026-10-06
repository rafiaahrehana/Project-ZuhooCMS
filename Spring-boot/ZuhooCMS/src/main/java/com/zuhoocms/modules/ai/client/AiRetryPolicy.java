package com.zuhoocms.modules.ai.client;

import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;

import java.io.IOException;

/** Retryable transport failures are 429, 5xx and I/O timeouts; other 4xx, unparseable bodies and programming errors fail identically on retry. */
public final class AiRetryPolicy {

    private AiRetryPolicy() {}

    public static boolean isRetryable(Throwable e) {
        if (e instanceof HttpStatusCodeException http) {
            int status = http.getStatusCode().value();
            return status == 429 || status >= 500;
        }
        return e instanceof ResourceAccessException || e instanceof IOException;
    }
}
