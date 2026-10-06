package com.zuhoocms.modules.itam.offboarding;

public class OffboardingChecklistMapper {

    /** employeeName comes from the caller (ItamEmployeeGuard.fullNames, one batch query): the Employee proxy would be one query per row and throws EntityNotFoundException for terminated employees under @SQLRestriction. */
    public static OffboardingChecklistResponse toResponse(OffboardingChecklist entity, String employeeName) {
        if (entity == null) {
            return null;
        }

        return OffboardingChecklistResponse.builder()
                .id(entity.getId())
                .employeeId(entity.getEmployee() != null ? entity.getEmployee().getId() : null)
                .employeeName(employeeName)
                .offboardingDate(entity.getOffboardingDate())
                .targetCompletionDate(entity.getTargetCompletionDate())
                .hardwareCollected(entity.isHardwareCollected())
                .hardwareCollectedDate(entity.getHardwareCollectedDate())
                .hardwareCollectedBy(entity.getHardwareCollectedBy())
                .hardwareNotes(entity.getHardwareNotes())
                .licensesRevoked(entity.isLicensesRevoked())
                .licensesRevokedDate(entity.getLicensesRevokedDate())
                .licensesNotes(entity.getLicensesNotes())
                .accessRevoked(entity.isAccessRevoked())
                .accessRevokedDate(entity.getAccessRevokedDate())
                .accessNotes(entity.getAccessNotes())
                .dataHandedOver(entity.isDataHandedOver())
                .dataHandoverDate(entity.getDataHandoverDate())
                .dataHandoverNotes(entity.getDataHandoverNotes())
                .exitInterviewCompleted(entity.isExitInterviewCompleted())
                .exitInterviewDate(entity.getExitInterviewDate())
                .exitInterviewNotes(entity.getExitInterviewNotes())
                .completed(entity.isCompleted())
                .completionDate(entity.getCompletionDate())
                .completedBy(entity.getCompletedBy())
                .completionPercentage(entity.getCompletionPercentage())
                .overallNotes(entity.getOverallNotes())
                .createdAt(entity.getCreatedAt())
                .updatedAt(entity.getUpdatedAt())
                .build();
    }
}
