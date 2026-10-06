package com.zuhoocms.modules.servicedesk.servicetemplate;

import org.springframework.security.access.prepost.PreAuthorize;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/service-templates")
@RequiredArgsConstructor
public class ServiceTemplateController {

    private final ServiceTemplateService templateService;

    // Templates are platform-owned (no company column; tenant services point at them), so only platform admins may write them. Reads stay open.
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    @PostMapping
    public ResponseEntity<ServiceTemplateResponse> create(@Valid @RequestBody ServiceTemplateRequest request) {
        return ResponseEntity.ok(templateService.create(request));
    }

    @PreAuthorize("hasRole('SUPER_ADMIN')")
    @PutMapping("/{id}")
    public ResponseEntity<ServiceTemplateResponse> update(@PathVariable Long id, @Valid @RequestBody ServiceTemplateRequest request) {
        return ResponseEntity.ok(templateService.update(id, request));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ServiceTemplateResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(templateService.getById(id));
    }

    @GetMapping
    public ResponseEntity<Page<ServiceTemplateResponse>> listAll(
            @RequestParam(defaultValue = "true") boolean activeOnly,
            Pageable pageable) {
        return ResponseEntity.ok(templateService.listAll(activeOnly, pageable));
    }

    @GetMapping("/category/{categoryId}")
    public ResponseEntity<List<ServiceTemplateResponse>> listByCategory(@PathVariable Long categoryId) {
        return ResponseEntity.ok(templateService.listByCategory(categoryId));
    }

    @PreAuthorize("hasRole('SUPER_ADMIN')")
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        templateService.delete(id);
        return ResponseEntity.ok().build();
    }
}
