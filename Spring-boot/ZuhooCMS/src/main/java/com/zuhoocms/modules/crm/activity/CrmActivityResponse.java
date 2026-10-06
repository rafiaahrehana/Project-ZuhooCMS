package com.zuhoocms.modules.crm.activity;

import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

@Getter @Setter
public class CrmActivityResponse {
    private Long id;
    private CrmActivityType type;
    private String subject;
    private String description;
    private LocalDateTime activityDate;
    private LocalDateTime scheduledAt;
    private boolean completed;
    // Echoed back so the caller can render the reminder it just set and the dashboard widget and timeline agree on what is outstanding.
    private LocalDateTime followUpAt;
    private boolean followUpDone;
    private boolean systemGenerated;
    private Long clientId;
    private Long opportunityId;
    private String opportunityName;
    private Long performedById;
    private String performedByName;
    private LocalDateTime createdAt;
}
