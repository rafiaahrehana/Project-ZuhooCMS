package com.zuhoocms.modules.support.agent;

import jakarta.validation.constraints.*;
import lombok.*;

@Data @NoArgsConstructor @AllArgsConstructor(access = AccessLevel.PACKAGE) @Builder
public class SupportAgentRequest {

    private Long userId;

    private String department;
    private String specialization;

    // No default: null on update means "keep the current status"; create() treats null as ACTIVE.
    private SupportAgentStatus status;

    @Min(value = 1)
    @Builder.Default
    private int maxConcurrentTickets = 10;

    private String notes;
}
