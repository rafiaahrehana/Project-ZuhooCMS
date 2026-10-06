package com.zuhoocms.auth.role.controller;

import com.zuhoocms.auth.role.dto.PermissionResponse;
import com.zuhoocms.auth.role.entity.Permission;
import com.zuhoocms.auth.role.repository.PermissionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Comparator;
import java.util.List;

/** Read-only catalog of every permission the app knows about (seeded from PermissionCode at boot). */
@RestController
@RequestMapping("/api/permissions")
@RequiredArgsConstructor
public class PermissionController {

    private final PermissionRepository permissionRepository;

    /**
     * Gated like every mapping on CustomRoleController, which is the only thing that consumes this list: the role
     * permission editor. Ungated it handed all 199 permission codes to any authenticated caller - including a CLIENT,
     * who is a tenant's customer and has no business reading the shape of their supplier's internal authorisation
     * model. The tell was structural: this controller goes straight to a repository with no service between, while
     * all eight of its neighbours sit behind a role check.
     */
    @PreAuthorize("hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @GetMapping
    public List<PermissionResponse> getAll() {
        return permissionRepository.findAll().stream()
                .map(this::toResponse)
                .sorted(Comparator.comparing(PermissionResponse::getCode))
                .toList();
    }

    private PermissionResponse toResponse(Permission p) {
        String module = p.getCode().contains("_") ? p.getCode().substring(0, p.getCode().indexOf('_')) : p.getCode();
        return PermissionResponse.builder()
                .id(p.getId())
                .code(p.getCode())
                .name(p.getName())
                .description(p.getDescription())
                .module(module)
                .build();
    }
}
