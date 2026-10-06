package com.zuhoocms.modules.servicedesk.requeststatus;

import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.auth.user.User;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "request_status_history")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class RequestStatusHistory {

    /** What the timeline shows for a change no signed-in user made. */
    public static final String SYSTEM_ACTOR_NAME = "System";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "request_id", nullable = false)
    private ServiceRequest serviceRequest;

    /**
     * Null when the platform itself made the change - the payment sweep's auto-cancellation runs with no signed-in
     * user - so the column is deliberately nullable. {@code ddl-auto=update} never relaxes an existing NOT NULL, so
     * {@link RequestStatusHistoryActorMigration} drops it on the live schema.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "changed_by_id")
    private User changedBy;

    /**
     * Who the timeline names, stamped at write time: the actor's full name, or "System" for a job-originated row.
     * Kept beside the association so a row still reads sensibly after the user is renamed or removed, and so a row
     * with no actor is plainly the system rather than an actor the reader failed to load. Null on rows written
     * before this column existed; the mapper falls back to the associated user's name for those.
     */
    @Column(name = "changed_by_name")
    private String changedByName;

    @Enumerated(EnumType.STRING)
    private ServiceRequestStatus oldStatus;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ServiceRequestStatus newStatus;

    @Column(columnDefinition = "TEXT")
    private String reason;

    // Denormalised for fast audit queries.
    private Long companyId;

    @Column(nullable = false)
    @Builder.Default
    private LocalDateTime changedAt = LocalDateTime.now();
}
