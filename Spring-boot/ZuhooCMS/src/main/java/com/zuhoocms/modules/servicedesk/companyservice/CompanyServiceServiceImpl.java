package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.servicedesk.servicecategory.ServiceCategory;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplate;
import com.zuhoocms.enums.ServicePriceType;
import com.zuhoocms.enums.ServiceRequestPriority;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.servicedesk.servicecategory.ServiceCategoryRepository;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor

public class CompanyServiceServiceImpl implements CompanyServiceService {

    private final CompanyServiceRepository   companyServiceRepository;
    private final ServiceCategoryRepository  categoryRepository;
    private final WorkflowTemplateRepository templateRepository;
    private final com.zuhoocms.modules.servicedesk.servicetemplate.ServiceTemplateRepository serviceTemplateRepository;
    private final SecurityUtil               securityUtil;
    private final AuthorizationService       authorizationService;
    private final com.zuhoocms.modules.company.CompanyRepository companyRepository;

    @Override
    @Transactional
    public CompanyServiceResponse create(CompanyServiceRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_CREATE);
        Long companyId = requireCompanyId();

        ServiceCategory category = null;
        if (request.getCategoryId() != null) {
            category = categoryRepository.findByIdAndCompanyId(request.getCategoryId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Service category not found: " + request.getCategoryId()));
        }

        WorkflowTemplate workflow = null;
        if (request.getWorkflowTemplateId() != null) {
            workflow = templateRepository
                .findByIdAndCompanyId(request.getWorkflowTemplateId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Workflow template not found: " + request.getWorkflowTemplateId()));
        }

        com.zuhoocms.modules.servicedesk.servicetemplate.ServiceTemplate serviceTemplate = null;
        if (request.getServiceTemplateId() != null) {
            serviceTemplate = serviceTemplateRepository.findById(request.getServiceTemplateId())
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Service template not found: " + request.getServiceTemplateId()));
        }

        CompanyService service = CompanyService.builder()
            .name(request.getName())
            .nameBn(request.getNameBn())
            .description(request.getDescription())
            .descriptionBn(request.getDescriptionBn())
            .price(request.getPrice())
            .priceType(request.getPriceType() != null ? request.getPriceType() : ServicePriceType.FIXED)
            // Default to the company's base currency, not "USD": invoices are raised in this currency and nothing supplies an exchange rate.
            .currency(request.getCurrency() != null && !request.getCurrency().isBlank()
                ? request.getCurrency().trim().toUpperCase()
                : companyRepository.findById(companyId).map(Company::getBaseCurrency).orElse("BDT"))
            .estimatedDays(request.getEstimatedDays())
            .defaultPriority(request.getDefaultPriority() != null
                ? request.getDefaultPriority() : ServiceRequestPriority.NORMAL)
            .company(companyRef(companyId))
            .category(category)
            .workflowTemplate(workflow)
            .serviceTemplate(serviceTemplate)
            .featured(Boolean.TRUE.equals(request.getFeatured()))
            .remote(Boolean.TRUE.equals(request.getRemote()))
            .onSite(Boolean.TRUE.equals(request.getOnSite()))
            .online(Boolean.TRUE.equals(request.getOnline()))
            .maximumOrders(request.getMaximumOrders())
            .autoApproval(Boolean.TRUE.equals(request.getAutoApproval()))
            .requiresQuotation(Boolean.TRUE.equals(request.getRequiresQuotation()))
            .requiresDocuments(Boolean.TRUE.equals(request.getRequiresDocuments()))
            .supportsCustomWorkflow(Boolean.TRUE.equals(request.getSupportsCustomWorkflow()))
            .aiAssisted(Boolean.TRUE.equals(request.getAiAssisted()))
            .visibility(request.getVisibility() != null ? request.getVisibility() : com.zuhoocms.enums.ServiceVisibility.DRAFT)
            .build();

        companyServiceRepository.save(service);
        
        return CompanyServiceMapper.toResponse(service);
    }

    @Override
    @Transactional(readOnly = true)
    public CompanyServiceResponse getById(Long id) {
        // The list beside this one checks the same code; reading one service by id was open to any member of the
        // company. findInTenant scopes it, so this was never a cross-tenant read - only an ungated one.
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_VIEW);
        return CompanyServiceMapper.toResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<CompanyServiceResponse> listAll(Long categoryId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_VIEW);
        Long companyId = requireCompanyId();
        Page<CompanyService> page = categoryId != null
            ? companyServiceRepository.findByCompanyIdAndCategoryId(companyId, categoryId, pageable)
            : companyServiceRepository.findByCompanyId(companyId, pageable);
        return page.map(CompanyServiceMapper::toResponse);
    }

    // Deliberately not gated by SERVICE_CATALOG_VIEW: the Requests and Packages pickers need it for users holding only SERVICE_REQUEST_VIEW/SERVICE_PACKAGE_VIEW.
    @Override
    @Transactional(readOnly = true)
    public List<CompanyServiceResponse> listActive() {
        return companyServiceRepository.findByCompanyIdAndActiveTrue(requireCompanyId())
            .stream().map(CompanyServiceMapper::toResponse).toList();
    }

    @Override
    @Transactional
    public CompanyServiceResponse update(Long id, CompanyServiceRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();
        CompanyService service = findInTenant(id);

        if (request.getName()            != null) service.setName(request.getName());
        if (request.getNameBn()          != null) service.setNameBn(request.getNameBn());
        if (request.getDescription()     != null) service.setDescription(request.getDescription());
        if (request.getDescriptionBn()   != null) service.setDescriptionBn(request.getDescriptionBn());
        if (request.getPrice()           != null) service.setPrice(request.getPrice());
        if (request.getPriceType()       != null) service.setPriceType(request.getPriceType());
        if (request.getEstimatedDays()   != null) service.setEstimatedDays(request.getEstimatedDays());
        if (request.getDefaultPriority() != null) service.setDefaultPriority(request.getDefaultPriority());
        // Trimmed and upper-cased the same way create does. Assigned raw, " bdt " and "BDT" were two different
        // currencies on the same service depending on which path wrote it.
        if (request.getCurrency() != null && !request.getCurrency().isBlank()) {
            service.setCurrency(request.getCurrency().trim().toUpperCase());
        }
        if (request.getFeatured() != null) service.setFeatured(request.getFeatured());
        if (request.getRemote() != null) service.setRemote(request.getRemote());
        if (request.getOnSite() != null) service.setOnSite(request.getOnSite());
        if (request.getOnline() != null) service.setOnline(request.getOnline());
        if (request.getMaximumOrders()   != null) service.setMaximumOrders(request.getMaximumOrders());
        if (request.getAutoApproval() != null) service.setAutoApproval(request.getAutoApproval());
        if (request.getRequiresQuotation() != null) service.setRequiresQuotation(request.getRequiresQuotation());
        if (request.getRequiresDocuments() != null) service.setRequiresDocuments(request.getRequiresDocuments());
        if (request.getSupportsCustomWorkflow() != null) service.setSupportsCustomWorkflow(request.getSupportsCustomWorkflow());
        if (request.getAiAssisted() != null) service.setAiAssisted(request.getAiAssisted());
        if (request.getVisibility()      != null) service.setVisibility(request.getVisibility());

        if (request.getCategoryId() != null) {
            service.setCategory(categoryRepository.findByIdAndCompanyId(request.getCategoryId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Service category not found: " + request.getCategoryId())));
        }
        if (request.getWorkflowTemplateId() != null) {
            service.setWorkflowTemplate(
                templateRepository.findByIdAndCompanyId(request.getWorkflowTemplateId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Workflow template not found: " + request.getWorkflowTemplateId())));
        }
        // Accepted on create and silently dropped here, so the web's template picker did nothing on an edit: you
        // chose a different template, saved, got a 200 and the old one back. Not company-scoped because service
        // templates are platform-level and carry no company - the same findById create uses.
        if (request.getServiceTemplateId() != null) {
            service.setServiceTemplate(serviceTemplateRepository.findById(request.getServiceTemplateId())
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Service template not found: " + request.getServiceTemplateId())));
        }

        return CompanyServiceMapper.toResponse(service);
    }

    @Override
    @Transactional
    public CompanyServiceResponse toggleActive(Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        CompanyService service = findInTenant(id);
        service.setActive(!service.isActive());
        return CompanyServiceMapper.toResponse(service);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_DELETE);
        CompanyService service = findInTenant(id);
        service.softDelete();
        companyServiceRepository.save(service);
    }

    private CompanyService findInTenant(Long id) {
        return companyServiceRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Service not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }
}
