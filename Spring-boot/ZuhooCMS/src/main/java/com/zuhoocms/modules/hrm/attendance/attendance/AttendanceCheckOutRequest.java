package com.zuhoocms.modules.hrm.attendance.attendance;

import jakarta.validation.constraints.NotNull;
import lombok.*;
import java.time.LocalTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AttendanceCheckOutRequest {

    private LocalTime checkOutTime;

    private AttendanceMethod method;

    private Long deviceId;

    private String latitude;
    private String longitude;
    private String location;

    private String earlyDepartureReason;

    /**
     * The check-out selfie, as one of this app's own uploaded-file URLs. Never required, unlike the check-in
     * selfie: somebody already inside for the day must not be locked out because a camera failed.
     */
    private String selfieUrl;
}
