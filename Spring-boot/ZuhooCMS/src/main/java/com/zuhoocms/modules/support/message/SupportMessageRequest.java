package com.zuhoocms.modules.support.message;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.*;
import lombok.*;

// AllArgsConstructor is package-private: a public one is picked up by Jackson as a creator and fails on any missing primitive - see ChartOfAccountRequest.
@Data @NoArgsConstructor @AllArgsConstructor(access = AccessLevel.PACKAGE) @Builder
public class SupportMessageRequest {

    @NotNull(message = "Ticket ID is required")
    private Long ticketId;

    @NotBlank(message = "Message is required")
    private String message;

    // Pin the key: Lombok's isInternal()/setInternal() make Jackson bind "internal", so Angular's "isInternal" is ignored and every internal note stores as external.
    @JsonProperty("isInternal")
    @Builder.Default
    private boolean isInternal = false;

    private String attachmentUrl;
    private String attachmentFileName;

    // Ignored - the sender is always the authenticated caller.
    private Long sentByUserId;
    @Builder.Default
    private String messageType = "TEXT";
    @JsonProperty("isResolution")
    @Builder.Default
    private boolean isResolution = false;
}
