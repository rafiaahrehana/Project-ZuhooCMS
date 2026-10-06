package com.zuhoocms.modules.hrm.attendance.settings;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

/**
 * Office-location policy for the caller's own company.
 *
 * Reading is open to anyone who can see attendance, because a flagged
 * check-in is not explicable without knowing the radius behind it, and the
 * mobile app reads the radius to decide whether to ask for a location at all.
 * Changing it takes COMPANY_SETTINGS - it decides whether every employee's
 * check-in gets flagged for review.
 */
@RestController
@RequestMapping("/api/hr/attendance-location-settings")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class AttendanceLocationSettingsController {

    private final AttendanceLocationSettingsService service;
    private final AuthorizationService authorizationService;

    /**
     * No permission check beyond being an employee or the owner of this company, deliberately.
     *
     * It used to require ATTENDANCE_VIEW or COMPANY_SETTINGS, which an ordinary employee has neither of - so the
     * phone apps read a 403, treated enforcement as off, sent a check-in with no selfie, and were refused by
     * check-in with "A selfie is required to check in." The lockout survived for exactly the people it affected,
     * while the comment above claimed the mobile app reads this.
     *
     * Nothing here is confidential from the staff it applies to: it is the office they come to and the rule their
     * own punches are judged against. Writing it still takes COMPANY_SETTINGS, because that is the decision.
     */
    @GetMapping
    public ResponseEntity<AttendanceLocationSettingsResponse> get() {
        return ResponseEntity.ok(
                AttendanceLocationSettingsResponse.from(service.getOrCreateForCurrentCompany()));
    }

    @PutMapping
    public ResponseEntity<AttendanceLocationSettingsResponse> update(
            @Valid @RequestBody AttendanceLocationSettingsRequest request) {
        authorizationService.checkPermission(PermissionCode.COMPANY_SETTINGS);
        return ResponseEntity.ok(AttendanceLocationSettingsResponse.from(service.update(request)));
    }
}
