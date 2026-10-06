package com.zuhoocms.auth.impersonation;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/platform-admin")
@PreAuthorize("hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_AGENT', 'SUPPORT_MANAGER')")
public class ImpersonationController {

    private final ImpersonationService impersonationService;
    private final ImpersonationAuditLogRepository impersonationAuditLogRepository;

    // Narrower than the class-level roles: startImpersonation() mints COMPANY_OWNER power over the target tenant, so a plain SUPPORT_AGENT would gain finance/payroll/delete access to any company.
    @PostMapping("/companies/{companyId}/impersonate")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_MANAGER')")
    public ResponseEntity<ImpersonationResponse> impersonate(
            @PathVariable Long companyId,
            @Valid @RequestBody ImpersonateRequest request) {
        return ResponseEntity.ok(impersonationService.startImpersonation(companyId, request));
    }

    // Must also accept the impersonation token itself (whose authorities are the tenant role, which the class-level check would 403) because the Angular banner ends the session before restoring the admin's token; ownership is enforced in the service.
    @PostMapping("/impersonate/end")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_AGENT', 'SUPPORT_MANAGER') or @securityUtil.isImpersonating()")
    public ResponseEntity<Void> endImpersonation(@Valid @RequestBody EndImpersonationRequest request) {
        impersonationService.endImpersonation(request);
        return ResponseEntity.ok().build();
    }

    // Restricted to admins/managers, not plain SUPPORT_AGENT, matching SupportContextSwitchController.getContextSwitchHistory() for the same kind of compliance record.
    @GetMapping("/impersonate/history")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_MANAGER')")
    public ResponseEntity<Page<ImpersonationAuditLogResponse>> history(
            @RequestParam(required = false) Long companyId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        PageRequest pageable = PageRequest.of(Math.max(page, 0), Math.min(Math.max(size, 1), 100), Sort.by("startedAt").descending());
        Page<ImpersonationAuditLog> logs = companyId != null
                ? impersonationAuditLogRepository.findByCompanyIdOrderByStartedAtDesc(companyId, pageable)
                : impersonationAuditLogRepository.findAllByOrderByStartedAtDesc(pageable);
        return ResponseEntity.ok(logs.map(ImpersonationAuditLogResponse::from));
    }
}
