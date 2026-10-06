package com.zuhoocms.modules.hrm.payroll.settings;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/** Payroll policy for the caller's company: readable by anyone who can see payroll (a payslip needs its divisor), changeable only with COMPANY_SETTINGS. */
@RestController
@RequestMapping("/api/hr/payroll-settings")
@RequiredArgsConstructor
public class PayrollSettingsController {

    private final PayrollSettingsService service;
    private final AuthorizationService authorizationService;

    @GetMapping
    public ResponseEntity<PayrollSettings> get() {
        authorizationService.checkAnyPermission(PermissionCode.PAYROLL_VIEW, PermissionCode.COMPANY_SETTINGS);
        return ResponseEntity.ok(service.getOrCreateForCurrentCompany());
    }

    @PutMapping
    public ResponseEntity<PayrollSettings> update(@Valid @RequestBody PayrollSettingsRequest request) {
        authorizationService.checkPermission(PermissionCode.COMPANY_SETTINGS);
        return ResponseEntity.ok(service.update(request));
    }
}
