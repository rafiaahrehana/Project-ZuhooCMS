package com.zuhoocms.modules.ai.exception;


import com.zuhoocms.shared.exception.ApiException;
import org.springframework.http.HttpStatus;

public class AiPromptException extends ApiException {

    public AiPromptException(String message) {
        super(message, HttpStatus.BAD_REQUEST);
    }
}
