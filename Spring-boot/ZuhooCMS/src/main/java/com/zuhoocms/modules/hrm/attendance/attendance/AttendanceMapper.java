package com.zuhoocms.modules.hrm.attendance.attendance;

public class AttendanceMapper {

    public static AttendanceResponse toResponse(Attendance entity) {
        if (entity == null) return null;

        return AttendanceResponse.builder()
                .id(entity.getId())
                .companyId(entity.getCompanyId())
                .employeeId(entity.getEmployee() != null ? entity.getEmployee().getId() : null)
                .employeeName(entity.getEmployee() != null ? entity.getEmployee().getFullName() : null)
                .employeeNumber(entity.getEmployee() != null ? entity.getEmployee().getEmployeeNumber() : null)
                .attendanceDate(entity.getAttendanceDate())
                .checkInTime(entity.getCheckInTime())
                .checkInDateTime(entity.getCheckInDateTime())
                .checkInMethod(entity.getCheckInMethod())
                .checkInLocation(entity.getCheckInLocation())
                .checkInLatitude(entity.getCheckInLatitude())
                .checkInLongitude(entity.getCheckInLongitude())
                .checkInReason(entity.getCheckInReason())
                .checkOutTime(entity.getCheckOutTime())
                .checkOutDateTime(entity.getCheckOutDateTime())
                .checkOutMethod(entity.getCheckOutMethod())
                .checkOutLocation(entity.getCheckOutLocation())
                .checkInSelfieUrl(entity.getCheckInSelfieUrl())
                .checkOutSelfieUrl(entity.getCheckOutSelfieUrl())
                .locationFlagged(entity.isLocationFlagged())
                .locationFlagReason(entity.getLocationFlagReason())
                .distanceFromOfficeMeters(entity.getDistanceFromOfficeMeters())
                .status(entity.getStatus())
                .shiftType(entity.getShiftType())
                .isLate(entity.isLate())
                .lateMinutes(entity.getLateMinutes())
                .lateReason(entity.getLateReason())
                .isOvertime(entity.isOvertime())
                .overtimeHours(entity.getOvertimeHours())
                .leftEarly(entity.isLeftEarly())
                .earlyMinutes(entity.getEarlyMinutes())
                .earlyDepartureReason(entity.getEarlyDepartureReason())
                .totalWorkingHours(entity.getTotalWorkingHours())
                .isVerified(entity.isVerified())
                .verificationScore(entity.getVerificationScore())
                .approved(entity.isApproved())
                .approvedBy(entity.getApprovedBy())
                .approvedDateTime(entity.getApprovedDateTime())
                .notes(entity.getAdminNotes())
                .createdAt(entity.getCreatedAt())
                .updatedAt(entity.getUpdatedAt())
                .build();
    }
}