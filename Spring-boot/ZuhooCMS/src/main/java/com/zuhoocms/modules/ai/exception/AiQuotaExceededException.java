package com.zuhoocms.modules.ai.exception;

import com.zuhoocms.shared.exception.ApiException;
import org.springframework.http.HttpStatus;

public class AiQuotaExceededException extends ApiException {

    public AiQuotaExceededException(String message) {
        super(message, HttpStatus.TOO_MANY_REQUESTS);
    }
}
