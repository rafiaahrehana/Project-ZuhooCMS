package com.zuhoocms.modules.support.ticket;

public class SupportTicketMapper {

    public static SupportTicketResponse toResponse(SupportTicket entity) {
        if (entity == null) return null;

        return SupportTicketResponse.builder()
                .id(entity.getId())
                .companyId(entity.getCompanyId())
                .ticketNumber(entity.getTicketNumber())
                .ticketType(entity.getTicketType())
                .createdByName(entity.getCreatedBy() != null ? entity.getCreatedBy().getFullName() : null)
                .title(entity.getTitle())
                .description(entity.getDescription())
                .attachmentUrl(entity.getAttachmentUrl())
                .attachmentFileName(entity.getAttachmentFileName())
                .categoryName(entity.getCategory() != null ? entity.getCategory().getCategoryName() : null)
                .status(entity.getStatus())
                .priority(entity.getPriority())
                .source(entity.getSource())
                // getId() on a lazy proxy doesn't initialise it - no extra query.
                .assignedToAgentId(entity.getAssignedToAgent() != null ? entity.getAssignedToAgent().getId() : null)
                .assignedToAgentName(entity.getAssignedToAgent() != null && entity.getAssignedToAgent().getUser() != null
                        ? entity.getAssignedToAgent().getUser().getFullName() : null)
                .assignedEmployeeName(entity.getAssignedEmployee() != null && entity.getAssignedEmployee().getUser() != null
                        ? entity.getAssignedEmployee().getUser().getFullName() : null)
                .assignedDate(entity.getAssignedDate())
                .firstResponseTime(entity.getFirstResponseTime())
                .firstResponseDeadline(entity.getFirstResponseDeadline())
                .resolutionTime(entity.getResolutionTime())
                .resolutionDeadline(entity.getResolutionDeadline())
                // Either deadline missed counts as an SLA breach for the UI.
                .slaBreached(entity.isSlaBreached() || entity.isFirstResponseBreached())
                .resolutionNotes(entity.getResolutionNotes())
                .closedDate(entity.getClosedDate())
                .escalationLevel(entity.getEscalationLevel() != null ? entity.getEscalationLevel() : 1)
                .escalatedDate(entity.getEscalatedDate())
                .satisfactionRating(entity.getSatisfactionRating())
                .satisfactionFeedback(entity.getSatisfactionFeedback())
                .createdAt(entity.getCreatedAt())
                .updatedAt(entity.getUpdatedAt())
                .build();
    }

    public static SupportTicket toEntity(SupportTicketRequest request) {
        if (request == null) return null;

        return SupportTicket.builder()
                .title(request.getTitle())
                .description(request.getDescription())
                .priority(request.getPriority())
                .source(request.getSource())
                .build();
    }
}
