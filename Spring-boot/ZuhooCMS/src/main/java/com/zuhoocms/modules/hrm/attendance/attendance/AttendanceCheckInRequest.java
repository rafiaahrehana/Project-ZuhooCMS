package com.zuhoocms.modules.hrm.attendance.attendance;

import jakarta.validation.constraints.*;
import lombok.*;
import java.time.LocalTime;

// AllArgsConstructor is package-private (see ChartOfAccountRequest): a public one becomes Jackson's creator and fails on any missing primitive field.
@Data @NoArgsConstructor @AllArgsConstructor(access = AccessLevel.PACKAGE) @Builder
public class AttendanceCheckInRequest {

    private Long employeeId;

    private LocalTime checkInTime;

    private AttendanceMethod method;

    private Long deviceId;
    private String latitude;
    private String longitude;
    private String location;

    private String reason;
    private boolean verified;
    private double verificationScore;

    /**
     * The check-in selfie, as one of this app's own uploaded-file URLs. The Android app sends one on every
     * check-in; it was silently discarded while this field was missing, because FAIL_ON_UNKNOWN_PROPERTIES is off.
     * Required only when the company has GPS enforcement on - see AttendanceServiceImpl.checkIn.
     */
    private String selfieUrl;
}