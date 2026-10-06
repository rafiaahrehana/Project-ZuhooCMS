package com.zuhoocms.modules.servicedesk.servicetemplate;

import com.zuhoocms.modules.servicedesk.servicecategory.ServiceCategory;
import com.zuhoocms.modules.servicedesk.servicecategory.ServiceCategoryRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ServiceTemplateServiceImpl implements ServiceTemplateService {

    private final ServiceTemplateRepository templateRepository;
    private final ServiceCategoryRepository categoryRepository;
    private final AuthorizationService authorizationService;
    private final SecurityUtil securityUtil;

    @Override
    @Transactional
    public ServiceTemplateResponse create(ServiceTemplateRequest request) {
        requirePlatformAdmin();
        ServiceCategory category = categoryRepository.findById(request.getCategoryId())
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));

        ServiceTemplate template = ServiceTemplate.builder()
                .name(request.getName())
                .description(request.getDescription())
                .category(category)
                .defaultPrice(request.getDefaultPrice())
                .estimatedDays(request.getEstimatedDays())
                .iconUrl(request.getIconUrl())
                .active(request.isActive())
                .build();

        if (request.getFormFields() != null) {
            template.getFormFields().addAll(request.getFormFields().stream().map(f -> 
                TemplateFormField.builder()
                    .serviceTemplate(template)
                    .label(f.getLabel())
                    .fieldType(f.getFieldType())
                    .required(f.isRequired())
                    .validationRules(f.getValidationRules())
                    .sortOrder(f.getSortOrder())
                    .build()
            ).collect(Collectors.toList()));
        }

        if (request.getRequiredDocuments() != null) {
            template.getRequiredDocuments().addAll(request.getRequiredDocuments().stream().map(d -> 
                TemplateRequiredDocument.builder()
                    .serviceTemplate(template)
                    .docName(d.getDocName())
                    .description(d.getDescription())
                    .mandatory(d.isMandatory())
                    .maxAgeDays(d.getMaxAgeDays())
                    .allowedFormats(d.getAllowedFormats())
                    .sortOrder(d.getSortOrder())
                    .build()
            ).collect(Collectors.toList()));
        }

        if (request.getWorkflowStages() != null) {
            template.getWorkflowStages().addAll(request.getWorkflowStages().stream().map(s -> 
                TemplateWorkflowStage.builder()
                    .serviceTemplate(template)
                    .stageName(s.getStageName())
                    .stageDescription(s.getStageDescription())
                    .stageOrder(s.getStageOrder())
                    .requiresClientAction(s.isRequiresClientAction())
                    .requiresPayment(s.isRequiresPayment())
                    .isFinalStage(s.isFinalStage())
                    .build()
            ).collect(Collectors.toList()));
        }

        templateRepository.save(template);
        return ServiceTemplateMapper.toResponse(template);
    }

    @Override
    @Transactional
    public ServiceTemplateResponse update(Long id, ServiceTemplateRequest request) {
        requirePlatformAdmin();
        ServiceTemplate template = templateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Template not found"));

        if (request.getName() != null) template.setName(request.getName());
        if (request.getDescription() != null) template.setDescription(request.getDescription());
        if (request.getDefaultPrice() != null) template.setDefaultPrice(request.getDefaultPrice());
        if (request.getEstimatedDays() != null) template.setEstimatedDays(request.getEstimatedDays());
        if (request.getIconUrl() != null) template.setIconUrl(request.getIconUrl());
        template.setActive(request.isActive());

        if (request.getCategoryId() != null && !request.getCategoryId().equals(template.getCategory().getId())) {
            ServiceCategory category = categoryRepository.findById(request.getCategoryId())
                    .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
            template.setCategory(category);
        }

        templateRepository.save(template);
        return ServiceTemplateMapper.toResponse(template);
    }

    @Override
    @Transactional(readOnly = true)
    public ServiceTemplateResponse getById(Long id) {
        // Gated the same way as listAll below, which is the read beside it: platform admins pass, everyone else
        // needs SERVICE_TEMPLATE_VIEW. Reading one template by id was open to any authenticated user.
        if (!isPlatformAdmin()) authorizationService.checkPermission(PermissionCode.SERVICE_TEMPLATE_VIEW);
        return ServiceTemplateMapper.toResponse(templateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Template not found")));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceTemplateResponse> listAll(boolean activeOnly, Pageable pageable) {
        if (!isPlatformAdmin()) authorizationService.checkPermission(PermissionCode.SERVICE_TEMPLATE_VIEW);
        if (activeOnly) {
            return templateRepository.findByActive(true, pageable).map(ServiceTemplateMapper::toResponse);
        }
        return templateRepository.findAll(pageable).map(ServiceTemplateMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ServiceTemplateResponse> listByCategory(Long categoryId) {
        return templateRepository.findByCategoryIdAndActiveTrue(categoryId).stream()
                .map(ServiceTemplateMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void delete(Long id) {
        requirePlatformAdmin();
        ServiceTemplate template = templateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Template not found"));
        template.softDelete();
    }

    /** ServiceTemplate has no company column, so a tenant's COMPANY_OWNER (who passes every checkPermission) could rename or delete templates other tenants depend on; mutations are platform-admin only. */
    private void requirePlatformAdmin() {
        if (!isPlatformAdmin()) {
            throw new ForbiddenException("Service templates are platform-managed - only a platform admin can change them");
        }
    }

    private boolean isPlatformAdmin() {
        User user = securityUtil.getCurrentUser();
        return user != null && user.getRole() == Role.SUPER_ADMIN && !securityUtil.isImpersonating();
    }
}
