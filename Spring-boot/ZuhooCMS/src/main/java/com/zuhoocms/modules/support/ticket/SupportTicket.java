package com.zuhoocms.modules.support.ticket;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.support.agent.SupportAgent;
import com.zuhoocms.modules.support.category.SupportCategory;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.hrm.employee.Employee;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDate;
import java.time.LocalDateTime;

import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "support_tickets", indexes = {
        @Index(name = "idx_ticket_company", columnList = "company_id"),
        @Index(name = "idx_ticket_status", columnList = "status"),
        @Index(name = "idx_ticket_priority", columnList = "priority"),
        @Index(name = "idx_ticket_assigned", columnList = "assigned_to_agent_id"),
        @Index(name = "idx_ticket_created_by", columnList = "created_by_id")
}, uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "ticket_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SupportTicket extends BaseEntity {

    @Column(name = "company_id")
    private Long companyId; // Company that created the ticket

    @Column(name = "ticket_number", nullable = false)
    private String ticketNumber; // TKT-2024-00001

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    @Builder.Default
    private TicketType ticketType = TicketType.PLATFORM_SUPPORT;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "company_id", insertable = false, updatable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "created_by_id", nullable = false)
    private User createdBy; // Tenant platformuser who created ticket

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "client_id")
    private Client client; // Optional: points to CRM Client (B2C)

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assigned_to_employee_id")
    private Employee assignedEmployee; // Optional: points to internal Employee (B2C)

    private String title;
    private String description;

    // Optional screenshot/image attached when the ticket was raised.
    private String attachmentUrl;
    private String attachmentFileName;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id")
    private SupportCategory category;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private TicketStatus status = TicketStatus.NEW;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private TicketPriority priority = TicketPriority.MEDIUM;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private TicketSource source = TicketSource.PORTAL;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assigned_to_agent_id")
    private SupportAgent assignedToAgent; // Support agent handling

    private LocalDateTime assignedDate;

    private LocalDateTime firstResponseTime;
    private LocalDateTime resolutionTime;

    private LocalDateTime firstResponseDeadline;
    private LocalDateTime resolutionDeadline;

    // Resolution-deadline breach (set by SlaBreachScheduler).
    @Builder.Default
    private boolean slaBreached = false;

    // Tracked separately so a missed first response doesn't suppress the resolution-breach alert; the column default lets ddl-auto=update add it to a populated table.
    @Builder.Default
    @Column(name = "first_response_breached", nullable = false, columnDefinition = "boolean default false")
    private boolean firstResponseBreached = false;

    private String slaBreachReason;

    private String resolutionNotes;
    private LocalDateTime closedDate;
    private String closedBy;

    private Integer satisfactionRating; // 1-5 stars
    private String satisfactionFeedback;

    @Builder.Default
    private Integer escalationLevel = 1; // 1=First level, 2=Senior, 3=Manager
    private LocalDateTime escalatedDate;
    private String escalationReason;

    @Builder.Default
    private boolean requiresFollowUp = false;

    private LocalDate followUpDate;

    /** Statuses a ticket is still being worked in - everything except RESOLVED/CLOSED. */
    public static final java.util.Set<TicketStatus> ACTIVE_STATUSES = java.util.EnumSet.of(
            TicketStatus.NEW, TicketStatus.OPEN, TicketStatus.IN_PROGRESS,
            TicketStatus.WAITING, TicketStatus.ON_HOLD, TicketStatus.REOPENED);

    public boolean isActiveStatus() {
        return status != null && ACTIVE_STATUSES.contains(status);
    }

    /** Assigning never moves a ticket out of whatever active state it is in, except NEW/REOPENED -> OPEN. */
    public void assignToAgent(SupportAgent agent) {
        this.assignedToAgent = agent;
        this.assignedDate = LocalDateTime.now();
        if (this.status == TicketStatus.NEW || this.status == TicketStatus.REOPENED) {
            this.status = TicketStatus.OPEN;
        }
    }

    public void recordFirstResponse() {
        if (this.firstResponseTime == null) {
            this.firstResponseTime = LocalDateTime.now();
        }
    }

    public void resolve(String notes, String resolvedByName) {
        this.resolutionNotes = notes;
        this.resolutionTime = LocalDateTime.now();
        this.closedBy = resolvedByName;
        this.status = TicketStatus.RESOLVED;
    }

    public void close() {
        this.status = TicketStatus.CLOSED;
        this.closedDate = LocalDateTime.now();
    }

    /** RESOLVED/CLOSED -> REOPENED: clears the close/resolution record, resets the breach flags and restarts the SLA clock. */
    public void reopen(LocalDateTime newFirstResponseDeadline, LocalDateTime newResolutionDeadline) {
        this.status = TicketStatus.REOPENED;
        this.closedDate = null;
        this.closedBy = null;
        this.resolutionNotes = null;
        this.resolutionTime = null;
        this.slaBreached = false;
        this.firstResponseBreached = false;
        this.slaBreachReason = null;
        this.firstResponseDeadline = newFirstResponseDeadline;
        this.resolutionDeadline = newResolutionDeadline;
    }

    public boolean isOverdueSLA() {
        if (firstResponseTime == null && firstResponseDeadline != null && LocalDateTime.now().isAfter(firstResponseDeadline)) {
            return true;
        }
        if (resolutionDeadline != null && LocalDateTime.now().isAfter(resolutionDeadline)) {
            return true;
        }
        return false;
    }

    public long getResponseTimeMinutes() {
        if (firstResponseTime == null || getCreatedAt() == null) return -1;
        return java.time.temporal.ChronoUnit.MINUTES.between(getCreatedAt(), firstResponseTime);
    }

    public long getResolutionTimeMinutes() {
        if (resolutionTime == null || getCreatedAt() == null) return -1;
        return java.time.temporal.ChronoUnit.MINUTES.between(getCreatedAt(), resolutionTime);
    }
}
