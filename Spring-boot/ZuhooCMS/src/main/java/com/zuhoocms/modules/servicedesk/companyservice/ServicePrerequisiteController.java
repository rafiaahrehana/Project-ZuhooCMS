package com.zuhoocms.modules.servicedesk.companyservice;

import org.springframework.security.access.prepost.PreAuthorize;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/services/{serviceId}/prerequisites")
@RequiredArgsConstructor
public class ServicePrerequisiteController {

    private final ServicePrerequisiteService prerequisiteService;

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PostMapping
    public ResponseEntity<ServicePrerequisiteResponse> create(@PathVariable Long serviceId, @Valid @RequestBody ServicePrerequisiteRequest request) {
        return ResponseEntity.ok(prerequisiteService.create(serviceId, request));
    }

    // CLIENT included so a client can see what a service depends on before ordering; the service layer resolves the parent service inside the caller's company.
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'CLIENT')")
    @GetMapping
    public ResponseEntity<List<ServicePrerequisiteResponse>> listByService(@PathVariable Long serviceId) {
        return ResponseEntity.ok(prerequisiteService.listByService(serviceId));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long serviceId, @PathVariable Long id) {
        prerequisiteService.delete(serviceId, id);
        return ResponseEntity.ok().build();
    }
}
