package com.zuhoocms.modules.hrm.attendance.settings;

import lombok.*;

/**
 * Every field is nullable and only applied when present, so the settings page
 * can send a partial update without wiping the fields it did not render.
 */
// AllArgsConstructor is package-private (see AttendanceRequest): a public one becomes Jackson's creator and fails on any missing field.
@Data @NoArgsConstructor @AllArgsConstructor(access = AccessLevel.PACKAGE) @Builder
public class AttendanceLocationSettingsRequest {

    private Double officeLatitude;
    private Double officeLongitude;
    private Integer radiusMeters;
    private Boolean gpsEnforcementEnabled;
}
