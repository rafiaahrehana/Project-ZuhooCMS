package com.zuhoocms.modules.servicedesk.servicecategory;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

/** Categories are each company's own catalog, not a shared platform taxonomy, so everything is scoped by companyId and name uniqueness is per-company. */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/service-categories")
public class ServiceCategoryController {

    private final ServiceCategoryRepository categoryRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current user");
        }
        return companyId;
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'CLIENT')")
    @GetMapping
    public ResponseEntity<List<ServiceCategoryResponse>> getAll() {
        if (!"CLIENT".equals(securityUtil.getCurrentUser().getRole().name())) {
            authorizationService.checkPermission(PermissionCode.SERVICE_CATEGORY_VIEW);
        }
        return ResponseEntity.ok(
            categoryRepository.findByCompanyIdAndActiveTrueOrderBySortOrderAsc(requireCompanyId())
                .stream()
                .map(ServiceCategoryMapper::toResponse)
                .collect(Collectors.toList()));
    }

    /** Includes inactive categories: with the active-only GET, a disabled category could never be re-enabled. */
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @GetMapping("/all")
    public ResponseEntity<List<ServiceCategoryResponse>> getAllIncludingInactive() {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATEGORY_VIEW);
        return ResponseEntity.ok(
            categoryRepository.findByCompanyIdOrderBySortOrderAsc(requireCompanyId())
                .stream()
                .map(ServiceCategoryMapper::toResponse)
                .collect(Collectors.toList()));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'CLIENT')")
    @GetMapping("/{id}")
    public ResponseEntity<ServiceCategoryResponse> getById(@PathVariable Long id) {
        ServiceCategory category = categoryRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service category not found: " + id));
        return ResponseEntity.ok(ServiceCategoryMapper.toResponse(category));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PostMapping
    @Transactional
    public ResponseEntity<ServiceCategoryResponse> create(
            @Valid @RequestBody ServiceCategoryRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATEGORY_CREATE);
        Long companyId = requireCompanyId();
        if (categoryRepository.existsByCompanyIdAndName(companyId, request.getName()))
            throw new BadRequestException(
                "A service category with this name already exists");
        ServiceCategory category = ServiceCategory.builder()
            .companyId(companyId)
            .name(request.getName())
            .nameBn(request.getNameBn())
            .description(request.getDescription())
            .iconUrl(request.getIconUrl())
            .sortOrder(request.getSortOrder())
            .active(true)
            .build();
        categoryRepository.save(category);
        return new ResponseEntity<>(
            ServiceCategoryMapper.toResponse(category), HttpStatus.CREATED);
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<ServiceCategoryResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody ServiceCategoryRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATEGORY_UPDATE);
        Long companyId = requireCompanyId();
        ServiceCategory category = categoryRepository.findByIdAndCompanyId(id, companyId)
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service category not found: " + id));
        if (!category.getName().equalsIgnoreCase(request.getName())
                && categoryRepository.existsByCompanyIdAndName(companyId, request.getName())) {
            throw new BadRequestException("A service category with this name already exists");
        }
        category.setName(request.getName());
        category.setNameBn(request.getNameBn());
        category.setDescription(request.getDescription());
        category.setIconUrl(request.getIconUrl());
        category.setSortOrder(request.getSortOrder());
        return ResponseEntity.ok(ServiceCategoryMapper.toResponse(category));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PatchMapping("/{id}/toggle")
    @Transactional
    public ResponseEntity<ServiceCategoryResponse> toggle(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATEGORY_UPDATE);
        ServiceCategory category = categoryRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service category not found: " + id));
        category.setActive(!category.isActive());
        return ResponseEntity.ok(ServiceCategoryMapper.toResponse(category));
    }
}
