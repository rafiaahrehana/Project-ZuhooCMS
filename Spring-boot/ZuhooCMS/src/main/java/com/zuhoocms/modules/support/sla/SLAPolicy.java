package com.zuhoocms.modules.support.sla;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.support.ticket.TicketPriority;
import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "sla_policies")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SLAPolicy extends BaseEntity {

    private String policyName; // e.g., "Standard SLA"

    private String description;

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private TicketPriority applicablePriority;

    private int firstResponseTimeHours;

    private int resolutionTimeHours;

    @Builder.Default
    private boolean businessHoursOnly = true;

    @Builder.Default
    private boolean active = true;

    private String notes;
}