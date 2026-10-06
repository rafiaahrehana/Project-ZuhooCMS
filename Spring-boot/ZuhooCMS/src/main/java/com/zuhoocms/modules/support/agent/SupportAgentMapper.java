package com.zuhoocms.modules.support.agent;

public class SupportAgentMapper {

    public static SupportAgentResponse toResponse(SupportAgent entity) {
        if (entity == null) return null;

        return SupportAgentResponse.builder()
                .id(entity.getId())
                .userId(entity.getUser() != null ? entity.getUser().getId() : null)
                .userName(entity.getUser() != null ? entity.getUser().getUsername() : null)
                .fullName(entity.getUser() != null ? entity.getUser().getFullName() : null)
                .email(entity.getUser() != null ? entity.getUser().getEmail() : null)
                .department(entity.getDepartment())
                .specialization(entity.getSpecialization())
                .status(entity.getStatus())
                .totalTicketsHandled(entity.getTotalTicketsHandled())
                .avgResponseTimeMinutes(entity.getAvgResponseTimeMinutes())
                .avgResolutionTimeMinutes(entity.getAvgResolutionTimeMinutes())
                .satisfactionScore(entity.getSatisfactionScore())
                .acceptingTickets(entity.isAcceptingTickets())
                .maxConcurrentTickets(entity.getMaxConcurrentTickets())
                .lastActiveTime(entity.getLastActiveTime())
                .notes(entity.getNotes())
                .createdAt(entity.getCreatedAt())
                .updatedAt(entity.getUpdatedAt())
                .build();
    }

    public static SupportAgent toEntity(SupportAgentRequest request) {
        if (request == null) return null;

        return SupportAgent.builder()
                .department(request.getDepartment())
                .specialization(request.getSpecialization())
                .status(request.getStatus() != null ? request.getStatus() : SupportAgentStatus.ACTIVE)
                .maxConcurrentTickets(request.getMaxConcurrentTickets())
                .notes(request.getNotes())
                .build();
    }
}
