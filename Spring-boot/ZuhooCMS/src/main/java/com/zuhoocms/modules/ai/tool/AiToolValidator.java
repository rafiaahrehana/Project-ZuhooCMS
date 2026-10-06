package com.zuhoocms.modules.ai.tool;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Comparator;
import java.util.Set;
import java.util.stream.Collectors;

/** Runs a DTO's Bean Validation constraints, which a tool does not get from @Valid: without it, model-produced arguments like -500 or -3 hours went past the rules the UI enforces. */
@Component
@RequiredArgsConstructor
public class AiToolValidator {

    private final Validator validator;

    /** Null when valid, otherwise a short human-readable list of what is wrong. */
    public String problems(Object dto) {
        Set<ConstraintViolation<Object>> violations = validator.validate(dto);
        if (violations.isEmpty()) return null;
        return violations.stream()
            .sorted(Comparator.comparing(v -> v.getPropertyPath().toString()))
            .map(v -> v.getPropertyPath() + " " + v.getMessage())
            .collect(Collectors.joining("; "));
    }
}
