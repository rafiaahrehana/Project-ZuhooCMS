package com.zuhoocms.modules.servicedesk.workflow.workflow;

import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStage;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRepository;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRequest;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageResponse;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplate;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateRepository;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateRequest;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateResponse;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.WorkflowSuggestionPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;

import java.util.List;

@Service
@RequiredArgsConstructor

public class WorkflowServiceImpl implements WorkflowService {

    private final WorkflowTemplateRepository templateRepository;
    private final WorkflowStageRepository stageRepository;
    private final SecurityUtil               securityUtil;
    private final AuthorizationService       authorizationService;
    private final AiService                  aiService;
    private final AiTransactionBoundary      aiTx;
    private final com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository serviceRequestRepository;

    @Override
    @Transactional
    public WorkflowTemplateResponse createTemplate(WorkflowTemplateRequest request) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_CREATE);
        Long companyId = requireCompanyId();
        if (templateRepository.existsByCompanyIdAndName(companyId, request.getName())) {
            throw new BadRequestException(
                    "A workflow template named '" + request.getName() + "' already exists");
        }
        WorkflowTemplate template = WorkflowTemplate.builder()
                .name(request.getName())
                .description(request.getDescription())
                .company(companyRef(companyId))
                .version(1)
                .active(true)
                .build();

        templateRepository.save(template);
        
        return WorkflowMapper.toResponse(template);
    }

    @Override
    @Transactional(readOnly = true)
    public WorkflowTemplateResponse getTemplateById(Long id) {
        // Gated like listTemplates below. Reading one template by id was open to any member of the company while
        // the list beside it asked for the code. listActiveTemplates stays open: it is the picker the service form
        // uses, the same exception the service catalogue makes for its own active list.
        authorizationService.checkPermission(PermissionCode.WORKFLOW_VIEW);
        return WorkflowMapper.toResponse(findTemplate(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<WorkflowTemplateResponse> listTemplates(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_VIEW);
        Long companyId = requireCompanyId();
        // Must be company-scoped: findAll(pageable) leaked every tenant's templates.
        return templateRepository.findByCompanyId(companyId, pageable)
                .map(WorkflowMapper::toResponse);
    }

    // Deliberately not gated by WORKFLOW_VIEW: the Services admin page's workflow picker is needed by users with SERVICE_CATALOG_VIEW only.
    @Override
    @Transactional(readOnly = true)
    public List<WorkflowTemplateResponse> listActiveTemplates() {
        Long companyId = requireCompanyId();
        // Must be company-scoped: findByActiveTrue() leaked cross-tenant data.
        return templateRepository.findByCompanyIdAndActiveTrue(companyId)
                .stream()
                .map(WorkflowMapper::toResponse)
                .toList();
    }

    @Override
    @Transactional
    public WorkflowTemplateResponse updateTemplate(Long id, WorkflowTemplateRequest request) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_UPDATE);
        Long companyId = requireCompanyId();
        WorkflowTemplate template = findTemplate(id);

        if (!template.getName().equals(request.getName())
                && templateRepository.existsByCompanyIdAndName(companyId, request.getName())) {
            throw new BadRequestException(
                    "A workflow template named '" + request.getName() + "' already exists");
        }

        template.setName(request.getName());
        if (request.getDescription() != null)
            template.setDescription(request.getDescription());
        template.setVersion(template.getVersion() + 1);

        templateRepository.save(template);
        return WorkflowMapper.toResponse(template);
    }

    @Override
    @Transactional
    public WorkflowTemplateResponse toggleTemplate(Long id) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_UPDATE);
        WorkflowTemplate template = findTemplate(id);

        if (template.isActive()) {
            boolean hasActiveStages = template.getStages().stream()
                    .anyMatch(s -> !s.isDeleted());
            if (hasActiveStages) {
                throw new BadRequestException(
                    "Cannot deactivate a workflow template that still has stages. Remove all stages first.");
            }
        }

        template.setActive(!template.isActive());
        templateRepository.save(template);
        
        return WorkflowMapper.toResponse(template);
    }

    @Override
    @Transactional
    public void deleteTemplate(Long id) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_DELETE);
        WorkflowTemplate template = findTemplate(id);

        if (!template.getStages().isEmpty()) {
            throw new BadRequestException(
                    "Cannot delete a workflow template that still has stages. Remove all stages first.");
        }

        template.softDelete();
        templateRepository.save(template);
        
    }

    @Override
    @Transactional
    public WorkflowStageResponse addStage(Long templateId, WorkflowStageRequest request) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_UPDATE);
        Long companyId = requireCompanyId();
        WorkflowTemplate template = findTemplate(templateId);

        if (stageRepository.existsByWorkflowTemplateIdAndStageOrder(
                templateId, request.getStageOrder())) {
            throw new BadRequestException(
                    "Stage order " + request.getStageOrder() + " is already taken in this workflow");
        }
        // Appending is safe; inserting before an existing stage shifts the indexes in-flight requests are positioned by.
        boolean insertsBeforeExisting = stageRepository.findByWorkflowTemplateIdOrderByStageOrderAsc(templateId)
                .stream().anyMatch(s -> s.getStageOrder() > request.getStageOrder());
        if (insertsBeforeExisting) {
            guardNoInFlightRequests(templateId, "insert a stage before existing stages of");
        }

        WorkflowStage stage = WorkflowStage.builder()
                .name(request.getName())
                .description(request.getDescription())
                .stageOrder(request.getStageOrder())
                .estimatedDays(request.getEstimatedDays())
                .slaHours(request.getSlaHours())
                // Absent means false on a create, stated here rather than by a field initialiser on the request,
                // so that update can still tell "not mentioned" from "set to false".
                .requiresApproval(Boolean.TRUE.equals(request.getRequiresApproval()))
                .assigneeRole(request.getAssigneeRole())
                .requiresPayment(Boolean.TRUE.equals(request.getRequiresPayment()))
                .paymentPercent(request.getPaymentPercent())
                .workflowTemplate(template)
                .company(companyRef(companyId))
                .build();

        stageRepository.save(stage);
        template.setVersion(template.getVersion() + 1);
        templateRepository.save(template);

        
        return WorkflowMapper.toStageResponse(stage);
    }

    @Override
    @Transactional
    public WorkflowStageResponse updateStage(Long templateId, Long stageId,
                                             WorkflowStageRequest request) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_UPDATE);
        findTemplate(templateId);

        WorkflowStage stage = stageRepository.findById(stageId)
                .filter(s -> s.getWorkflowTemplate().getId().equals(templateId))
                .orElseThrow(() -> new ResourceNotFoundException("Stage not found: " + stageId));

        if (!stage.getStageOrder().equals(request.getStageOrder())
                && stageRepository.existsByWorkflowTemplateIdAndStageOrder(
                templateId, request.getStageOrder())) {
            throw new BadRequestException(
                    "Stage order " + request.getStageOrder() + " is already taken");
        }
        // Reordering shifts the stage indexes in-flight requests are positioned by; editing name/SLA/approval in place does not.
        if (!stage.getStageOrder().equals(request.getStageOrder())) {
            guardNoInFlightRequests(templateId, "reorder stages of");
        }

        stage.setName(request.getName());
        stage.setStageOrder(request.getStageOrder());
        stage.setEstimatedDays(request.getEstimatedDays());
        stage.setSlaHours(request.getSlaHours());
        // Guarded, like description below. Unconditional, an update that omitted these keys turned the approval
        // gate and milestone billing off and answered 200 - the two gates on this entity that matter most.
        if (request.getRequiresApproval() != null) stage.setRequiresApproval(request.getRequiresApproval());
        stage.setAssigneeRole(request.getAssigneeRole());
        if (request.getRequiresPayment() != null) stage.setRequiresPayment(request.getRequiresPayment());
        stage.setPaymentPercent(request.getPaymentPercent());
        if (request.getDescription() != null)
            stage.setDescription(request.getDescription());

        stageRepository.save(stage);

        WorkflowTemplate template = stage.getWorkflowTemplate();
        template.setVersion(template.getVersion() + 1);
        templateRepository.save(template);

        return WorkflowMapper.toStageResponse(stage);
    }

    @Override
    @Transactional
    public void deleteStage(Long templateId, Long stageId) {
        authorizationService.checkPermission(PermissionCode.WORKFLOW_UPDATE);
        WorkflowTemplate template = findTemplate(templateId);

        WorkflowStage stage = stageRepository.findById(stageId)
                .filter(s -> s.getWorkflowTemplate().getId().equals(templateId))
                .orElseThrow(() -> new ResourceNotFoundException("Stage not found: " + stageId));

        guardNoInFlightRequests(templateId, "delete a stage from");

        stage.softDelete();
        stageRepository.save(stage);

        template.setVersion(template.getVersion() + 1);
        templateRepository.save(template);

        
    }

    // No @Transactional on purpose: aiTx.load() commits before the provider call so no DB connection is held across it - see AiTransactionBoundary; lazy t.getStages() must be read inside the callback.
    @Override
    public WorkflowSuggestionResponse suggest(WorkflowSuggestionRequest request) {
        // The only method in this class that checked nothing, and the only one that calls a paid AI provider: any
        // employee could spend the company's AI budget. Gated on WORKFLOW_CREATE because what it returns is a draft
        // workflow to create - asking for a suggestion you could not then save is not a capability worth having.
        authorizationService.checkPermission(PermissionCode.WORKFLOW_CREATE);
        Long companyId = requireCompanyId();

        String prompt = aiTx.load(() -> {
            List<WorkflowTemplate> activeTemplates = templateRepository.findByCompanyIdAndActiveTrue(companyId);

            String existingSummary = activeTemplates.stream()
                .map(t -> "- " + t.getName() + ": " + t.getStages().stream()
                    .map(WorkflowStage::getName)
                    .reduce((a, b) -> a + " -> " + b)
                    .orElse("(no stages)"))
                .reduce((a, b) -> a + "\n" + b)
                .orElse(null);

            return WorkflowSuggestionPromptBuilder.builder()
                .setGoal(request.getGoal())
                .setExistingTemplatesSummary(existingSummary)
                .build();
        });

        String raw = aiService.generateRaw(AiFeature.WORKFLOW_SUGGESTION, prompt);
        WorkflowSuggestionResponse response = parseSuggestion(raw);
        return response;
    }

    /** Models wrap the demanded bare JSON in fences or prose, so strip fences and cut to the outer braces; invalid JSON falls back to the raw text rather than an error. */
    private WorkflowSuggestionResponse parseSuggestion(String raw) {
        WorkflowSuggestionResponse response = new WorkflowSuggestionResponse();
        String candidate = raw == null ? "" : raw.replaceAll("```(?:json)?", "").trim();
        int start = candidate.indexOf('{');
        int end = candidate.lastIndexOf('}');
        if (start >= 0 && end > start) {
            candidate = candidate.substring(start, end + 1);
            try {
                var mapper = new com.fasterxml.jackson.databind.ObjectMapper()
                        .configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
                WorkflowSuggestionResponse parsed = mapper.readValue(candidate, WorkflowSuggestionResponse.class);
                if (parsed.getName() != null && parsed.getStages() != null && !parsed.getStages().isEmpty()) {
                    response.setName(parsed.getName());
                    response.setStages(parsed.getStages());
                    return response;
                }
            } catch (com.fasterxml.jackson.core.JacksonException ignored) {
                // fall through to raw
            }
        }
        response.setSuggestion(raw);
        return response;
    }

    private static final List<ServiceRequestStatus> TERMINAL_REQUEST_STATUSES = List.of(
            ServiceRequestStatus.COMPLETED, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED);

    /** ServiceRequest.currentStage is a plain index into the ordered stage list, so structural edits are refused while open requests run on the template (until requests pin a stage id). */
    private void guardNoInFlightRequests(Long templateId, String action) {
        long inFlight = serviceRequestRepository.countInFlightByWorkflowTemplate(templateId, TERMINAL_REQUEST_STATUSES);
        if (inFlight > 0) {
            throw new BadRequestException("Cannot " + action + " this workflow while " + inFlight
                    + " open service request" + (inFlight == 1 ? " is" : "s are")
                    + " using it - complete, reject or cancel "
                    + (inFlight == 1 ? "it" : "them") + " first, or create a new workflow template version.");
        }
    }

    private WorkflowTemplate findTemplate(Long id) {
        return templateRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Workflow template not found: " + id));
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
