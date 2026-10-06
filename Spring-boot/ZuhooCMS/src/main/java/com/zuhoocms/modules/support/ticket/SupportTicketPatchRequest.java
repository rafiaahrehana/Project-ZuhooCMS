package com.zuhoocms.modules.support.ticket;

import jakarta.validation.constraints.Size;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * PATCH body: every field optional, only non-null ones applied, using the same JSON keys as SupportTicketRequest so the Angular edit form keeps working.
 * {@code status} is accepted alone, as the dashboard's inline selector sends it that way, and routes through the same guarded transitions as the action endpoints.
 */
@Data
@NoArgsConstructor
public class SupportTicketPatchRequest {

    @Size(max = 255, message = "Title must be at most 255 characters")
    private String title;

    private String description;

    private Long categoryId;

    private TicketPriority priority;

    private TicketStatus status;

    private String attachmentUrl;
    private String attachmentFileName;
}
