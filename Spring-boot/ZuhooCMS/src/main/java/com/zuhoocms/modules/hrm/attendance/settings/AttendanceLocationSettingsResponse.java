package com.zuhoocms.modules.hrm.attendance.settings;

import lombok.*;

/**
 * The wire shape of one company's office-location policy.
 *
 * A DTO rather than the entity itself (which is what the pre-deletion controller returned): the entity carries
 * companyId, the soft-delete flag and the audit timestamps, none of which the settings screen has any business
 * seeing. The four field names here are the ones the Android app's AttendanceLocationSettingsResponse reads.
 */
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class AttendanceLocationSettingsResponse {

    private Double officeLatitude;
    private Double officeLongitude;
    private Integer radiusMeters;
    private boolean gpsEnforcementEnabled;

    public static AttendanceLocationSettingsResponse from(AttendanceLocationSettings settings) {
        if (settings == null) return null;
        return AttendanceLocationSettingsResponse.builder()
                .officeLatitude(settings.getOfficeLatitude())
                .officeLongitude(settings.getOfficeLongitude())
                .radiusMeters(settings.getRadiusMeters())
                .gpsEnforcementEnabled(settings.isGpsEnforcementEnabled())
                .build();
    }
}
