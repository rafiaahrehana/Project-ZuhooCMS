package com.zuhoocms.modules.servicedesk.servicerequest;

import com.zuhoocms.core.automation.AutomationEventPublisher;
import com.zuhoocms.enums.*;
import com.zuhoocms.enums.SubscriptionStatus;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyService;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscription;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscriptionRepository;
import com.zuhoocms.modules.servicedesk.companyservice.ServicePackageService;
import com.zuhoocms.modules.servicedesk.requestcomment.AddCommentRequest;
import com.zuhoocms.modules.servicedesk.requeststatus.ChangeRequestStatusRequest;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.modules.servicedesk.requestcomment.RequestCommentResponse;
import com.zuhoocms.modules.servicedesk.requeststatus.RequestStatusHistoryResponse;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.servicedesk.requestcomment.RequestComment;
import com.zuhoocms.modules.servicedesk.requeststatus.RequestStatusHistory;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceRepository;
import com.zuhoocms.modules.servicedesk.requestcomment.RequestCommentRepository;
import com.zuhoocms.modules.servicedesk.requeststatus.RequestStatusHistoryRepository;
import com.zuhoocms.modules.servicedesk.task.TaskRepository;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRepository;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStage;
import com.zuhoocms.modules.servicedesk.approval.StageApproval;
import com.zuhoocms.modules.servicedesk.approval.StageApprovalRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.repository.RolePermissionRepository;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceService;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRequest;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceResponse;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceItemRequest;
import com.zuhoocms.modules.company.CompanyRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import com.zuhoocms.modules.ai.support.PreparedPrompt;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import com.zuhoocms.modules.servicedesk.dynamicform.ServiceFormField;
import com.zuhoocms.modules.servicedesk.dynamicform.ServiceFormFieldRepository;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.ServiceRequestSummaryPromptBuilder;
import com.zuhoocms.modules.ai.prompt.ServiceRequestReplyDraftPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import org.springframework.data.domain.PageRequest;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

@Slf4j
@Service
@RequiredArgsConstructor
public class ServiceRequestServiceImpl implements ServiceRequestService {

    private final ServiceRequestRepository serviceRequestRepository;
    private final com.zuhoocms.modules.servicedesk.document.RequiredDocumentRepository requiredDocumentRepository;
    private final com.zuhoocms.modules.servicedesk.companyservice.ServicePrerequisiteRepository servicePrerequisiteRepository;
    private final com.zuhoocms.modules.servicedesk.document.DocumentRepository documentRepository;
    private final TaskRepository taskRepository;
    private final RequestCommentRepository commentRepository;
    private final RequestStatusHistoryRepository historyRepository;
    private final CompanyServiceRepository companyServiceRepository;
    private final PackageSubscriptionRepository subscriptionRepository;
    private final ServicePackageService packageService;
    private final ClientRepository clientRepository;
    private final EmployeeRepository employeeRepository;
    private final WorkflowStageRepository workflowStageRepository;
    private final StageApprovalRepository stageApprovalRepository;
    private final NotificationService notificationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final RolePermissionRepository rolePermissionRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final CompanyRepository companyRepository;
    private final AutomationEventPublisher automationEventPublisher;
    private final ClientInvoiceService invoiceService;
    private final ServiceFormFieldRepository serviceFormFieldRepository;
    private final ObjectMapper objectMapper;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final org.springframework.transaction.PlatformTransactionManager transactionManager;

    @Override
    @Transactional
    public ServiceRequestResponse create(CreateServiceRequestRequest request) {
        Long companyId = requireCompanyId();
        User currentUser = securityUtil.getCurrentUser();

        // Scoped: the client is persisted on a request stamped with companyId and flows on into invoicing and
        // notifications, so a client record from another tenant must not be accepted here.
        Client client = clientRepository.findByUserIdAndCompanyId(currentUser.getId(), companyId)
            .orElseThrow(() -> new BadRequestException(
                "Only clients can submit service requests"));

        CompanyService service = companyServiceRepository
            .findByIdAndCompanyId(request.getHubServiceId(), companyId)
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service not found: " + request.getHubServiceId()));

        if (!service.isActive()) {
            throw new BadRequestException("This service is currently unavailable");
        }

        // maximumOrders caps open (non-terminal) orders; the service row is locked so concurrent orders can't both see "one slot left".
        if (service.getMaximumOrders() != null) {
            companyServiceRepository.findByIdAndCompanyIdForUpdate(service.getId(), companyId);
            long open = serviceRequestRepository.countOpenByService(companyId, service.getId(), TERMINAL_STATUSES);
            if (open >= service.getMaximumOrders()) {
                throw new BadRequestException("'" + service.getName()
                    + "' is fully booked (maximum " + service.getMaximumOrders()
                    + " open orders). Please try again later.");
            }
        }

        validatePrerequisites(companyId, client.getId(), service);

        PackageSubscription subscription = null;
        boolean overageConsumed = false;
        BigDecimal agreedPrice;

        if (request.getSubscriptionId() != null) {
            subscription = subscriptionRepository
                .findByIdAndCompanyId(request.getSubscriptionId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Subscription not found: " + request.getSubscriptionId()));

            if (!subscription.getClient().getId().equals(client.getId())) {
                throw new BadRequestException(
                    "This subscription does not belong to you");
            }
            if (subscription.getStatus() != SubscriptionStatus.ACTIVE) {
                throw new BadRequestException(
                    "Subscription is not active. Status: " + subscription.getStatus());
            }
            if (!subscription.getServicePackage().includesService(service.getId())) {
                throw new BadRequestException(
                    "Service '" + service.getName() +
                    "' is not included in your subscription package");
            }
            // Record whether THIS unit went past quota, so completion bills this request once instead of re-reading the live counter.
            PackageSubscription consumed = packageService.consumeQuota(subscription.getId());
            overageConsumed = consumed.getRequestQuota() != null
                && consumed.getRequestsUsed() > consumed.getRequestQuota();

            agreedPrice = BigDecimal.ZERO;

        } else {
            agreedPrice = request.getAgreedPrice() != null
                ? request.getAgreedPrice()
                : service.getPrice();
        }

        String formDataJson = validateAndSerializeFormData(
            companyId, service.getId(), request.getFormData());

        ServiceRequestPriority priority = request.getPriority() != null
            ? request.getPriority() : service.getDefaultPriority();
        // SLA is server-side: request.getSlaDeadline() is ignored so a client cannot pick their own deadline (DTO field kept only for payload binding).
        int slaHours = computeInitialSlaHours(service, priority);

        ServiceRequest sr = ServiceRequest.builder()
            .title(request.getTitle())
            .description(request.getDescription())
            .status(ServiceRequestStatus.PENDING)
            .priority(priority)
            .agreedPrice(agreedPrice)
            .slaHours(slaHours)
            .slaDeadline(LocalDateTime.now().plusHours(slaHours))
            .breachCount(0)
            .overageConsumed(overageConsumed)
            .formDataJson(formDataJson)
            .company(companyRef(companyId))
            .client(client)
            .companyService(service)
            .subscription(subscription)
            .build();

        serviceRequestRepository.save(sr);
        recordStatusChange(sr, null, ServiceRequestStatus.PENDING,
            "Request submitted", currentUser, companyId);

        // Without this, staff only learn of a new request by opening the Service Requests list.
        try {
            notifyAssignableStaff(companyId, NotificationType.REQUEST_SUBMITTED, "New Service Request",
                client.getClientCompanyName() + " submitted a new request: \"" + sr.getTitle() + "\"", sr.getId());
        } catch (Exception ex) {
            log.warn("New-request staff notification failed for request {}: {}", sr.getId(), ex.getMessage());
        }

        if (client.getUser() != null) {
            try {
                Company fullCompany = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendTicketCreatedEmail(client.getUser().getEmail(), client.getUser().getFirstName(), sr.getTitle(), branding);
            } catch (Exception ex) {
                log.warn("Ticket created email failed for client {}: {}", client.getUser().getEmail(), ex.getMessage());
            }
        }

        ServiceRequestResponse response = toResponse(sr);

        // Quotation services are invoiced in acceptQuotation() - invoicing here too billed the client twice.
        if (agreedPrice.compareTo(BigDecimal.ZERO) > 0 && !service.isRequiresQuotation()) {
            ClientInvoiceItemRequest item = ClientInvoiceItemRequest.builder()
                .description("Service Request: " + sr.getTitle())
                .quantity(new BigDecimal("1"))
                .unitPrice(agreedPrice)
                .build();

            ClientInvoiceRequest invoiceRequest = ClientInvoiceRequest.builder()
                .clientId(client.getId())
                .serviceRequestId(sr.getId())
                .invoiceDate(java.time.LocalDate.now())
                .dueDate(java.time.LocalDate.now().plusDays(3))
                .currency(service.getCurrency())
                .notes("Invoice for Service Request: " + sr.getTitle())
                .items(List.of(item))
                .build();

            ClientInvoiceResponse invoiceResponse = invoiceService.createForServiceRequest(companyId, invoiceRequest);
            sr.setInvoiceId(invoiceResponse.getId());
            serviceRequestRepository.save(sr);
            response.setInvoiceId(invoiceResponse.getId());

            invoiceService.sendInvoiceForServiceRequest(invoiceResponse.getId());
        }

        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public ServiceRequestResponse getById(Long id) {
        return toResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceRequestResponse> listAll(ServiceRequestStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SERVICE_REQUEST_VIEW);
        Long companyId = requireCompanyId();
        Page<ServiceRequest> page = status != null
            ? serviceRequestRepository.findByCompanyIdAndStatus(companyId, status, pageable)
            : serviceRequestRepository.findByCompanyId(companyId, pageable);
        return page.map(this::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceRequestResponse> listMyRequests(Pageable pageable) {
        Long companyId = requireCompanyId();
        User currentUser = securityUtil.getCurrentUser();
        Client client = clientRepository.findByUserId(currentUser.getId())
            .orElseThrow(() -> new BadRequestException("Client profile not found"));
        return serviceRequestRepository
            .findByCompanyIdAndClientId(companyId, client.getId(), pageable)
            .map(this::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceRequestResponse> listAssignedToMe(Pageable pageable) {
        Long companyId = requireCompanyId();
        User currentUser = securityUtil.getCurrentUser();
        Employee emp = employeeRepository.findByUserId(currentUser.getId())
            .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        return serviceRequestRepository
            .findByCompanyIdAndAssignedEmployeeId(companyId, emp.getId(), pageable)
            .map(this::toResponse);
    }

    @Override
    @Transactional
    public ServiceRequestResponse update(Long id, UpdateServiceRequestRequest request) {
        authorizationService.checkAnyPermission(
            PermissionCode.SERVICE_REQUEST_ASSIGN, PermissionCode.SERVICE_REQUEST_APPROVE,
            PermissionCode.SERVICE_REQUEST_CLOSE);
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        if (request.getTitle()       != null) sr.setTitle(request.getTitle());
        if (request.getDescription() != null) sr.setDescription(request.getDescription());
        if (request.getPriority()    != null) sr.setPriority(request.getPriority());
        if (request.getAgreedPrice() != null) sr.setAgreedPrice(request.getAgreedPrice());
        if (request.getSlaDeadline() != null) sr.setSlaDeadline(request.getSlaDeadline());
        if (request.getGovRefNumber() != null) sr.setGovRefNumber(request.getGovRefNumber());
        if (request.getGovRefType() != null) sr.setGovRefType(request.getGovRefType());

        if (request.getAssignedEmployeeId() != null) {
            Employee emp = employeeRepository
                .findByIdAndCompanyId(request.getAssignedEmployeeId(), requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Employee not found: " + request.getAssignedEmployeeId()));
            sr.setAssignedEmployee(emp);
            if (sr.getAssignedAt() == null) sr.setAssignedAt(LocalDateTime.now());
        }
        return toResponse(sr);
    }

    @Override
    @Transactional
    public ServiceRequestResponse changeStatus(Long id, ChangeRequestStatusRequest request) {
        // Terminal transitions need the "close" permission; other lifecycle moves only need the lighter "approve" one.
        ServiceRequestStatus targetStatus = request.getStatus();
        boolean isTerminal = targetStatus == ServiceRequestStatus.COMPLETED
            || targetStatus == ServiceRequestStatus.REJECTED
            || targetStatus == ServiceRequestStatus.CANCELLED;
        authorizationService.checkPermission(
            isTerminal ? PermissionCode.SERVICE_REQUEST_CLOSE : PermissionCode.SERVICE_REQUEST_APPROVE);

        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        ServiceRequestStatus oldStatus = sr.getStatus();
        ServiceRequestStatus newStatus = request.getStatus();
        User currentUser = securityUtil.getCurrentUser();

        guardTransition(oldStatus, newStatus);

        if ((oldStatus == ServiceRequestStatus.PENDING || oldStatus == ServiceRequestStatus.QUOTATION_PENDING)
                && (newStatus == ServiceRequestStatus.ASSIGNED || newStatus == ServiceRequestStatus.IN_PROGRESS)) {
            validateRequiredDocuments(sr);
        }

        // Every cancellation path goes through closeRequest(), which does quota release, invoice cancel/refund and permanentlyClosed.
        if (newStatus == ServiceRequestStatus.CANCELLED || newStatus == ServiceRequestStatus.REJECTED) {
            closeRequest(sr, newStatus, request.getReason(), currentUser, requireCompanyId(), false);
            return toResponse(sr);
        }

        applySlaPause(sr, oldStatus, newStatus);
        sr.setStatus(newStatus);
        if (newStatus == ServiceRequestStatus.COMPLETED) {
            boolean hasIncompleteTasks = sr.getTasks().stream()
                .anyMatch(task -> task.getStatus() != TaskStatus.COMPLETED && task.getStatus() != TaskStatus.CANCELLED);
            if (hasIncompleteTasks) {
                throw new BadRequestException("Cannot complete service request with active, incomplete tasks");
            }

            // Each approval stage needs an explicit APPROVED row: checking only "no PENDING row" let REJECTED and never-reached stages pass.
            if (sr.getCompanyService() != null && sr.getCompanyService().getWorkflowTemplate() != null) {
                List<WorkflowStage> stages = workflowStageRepository
                    .findByWorkflowTemplateIdOrderByStageOrderAsc(sr.getCompanyService().getWorkflowTemplate().getId());
                boolean anyStageNotApproved = stages.stream()
                    .filter(stage -> Boolean.TRUE.equals(stage.getRequiresApproval()))
                    .anyMatch(stage -> !stageApprovalRepository.existsByServiceRequestIdAndWorkflowStageIdAndStatus(
                        sr.getId(), stage.getId(), ApprovalStatus.APPROVED));
                if (anyStageNotApproved) {
                    throw new BadRequestException(
                        "Cannot complete service request: one or more workflow stages requiring approval have not been approved");
                }
            }

            sr.setCompletedAt(LocalDateTime.now());
            sr.setPermanentlyClosed(true);
            publishCompletedAfterCommit(requireCompanyId(), sr.getId(),
                sr.getClient() != null ? sr.getClient().getId() : null);
        }
        if (newStatus == ServiceRequestStatus.ASSIGNED && sr.getAssignedAt() == null)
            sr.setAssignedAt(LocalDateTime.now());

        recordStatusChange(sr, oldStatus, newStatus, request.getReason(),
            currentUser, requireCompanyId());
        notifyClientOnStatusChange(sr, newStatus);
        return toResponse(sr);
    }

    @Override
    @Transactional
    public ServiceRequestResponse assign(Long id, Long employeeId) {
        authorizationService.checkPermission(PermissionCode.SERVICE_REQUEST_ASSIGN);
        Long companyId = requireCompanyId();
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        Employee emp = employeeRepository.findByIdAndCompanyId(employeeId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException(
                "Employee not found: " + employeeId));

        if (sr.getStatus() == ServiceRequestStatus.PENDING) {
            validateRequiredDocuments(sr);
        }

        if (sr.getAssignedEmployee() != null && sr.getAssignedEmployee().getId().equals(employeeId)) {
            // Already assigned to this employee: don't duplicate history or emails
            return toResponse(sr);
        }

        ServiceRequestStatus old = sr.getStatus();
        sr.setAssignedEmployee(emp);
        sr.setAssignedAt(LocalDateTime.now());
        applySlaPause(sr, old, ServiceRequestStatus.ASSIGNED);
        sr.setStatus(ServiceRequestStatus.ASSIGNED);

        recordStatusChange(sr, old, ServiceRequestStatus.ASSIGNED,
            "Assigned to " + emp.getUser().getFullName(),
            securityUtil.getCurrentUser(), companyId);

        if (emp.getUser() != null) {
            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                NotificationType.REQUEST_ASSIGNED,
                "Request Assigned",
                "Service request \"" + sr.getTitle() + "\" has been assigned to you.",
                emp.getUser().getId(), companyId, sr.getId()
            ));

            try {
                Company fullCompany = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendTicketAssignedEmail(emp.getUser().getEmail(), emp.getUser().getFirstName(), sr.getTitle(), branding);
            } catch (Exception ex) {
                log.warn("Ticket assigned email failed for employee {}: {}", emp.getUser().getEmail(), ex.getMessage());
            }
        }
        return toResponse(sr);
    }

    @Override
    @Transactional
    public void cancel(Long id, String reason) {
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        User currentUser = securityUtil.getCurrentUser();
        // A client cannot self-cancel once staff is assigned and already working it; staff keep unrestricted cancel.
        if (currentUser.getRole() == Role.CLIENT && sr.getAssignedEmployee() != null) {
            throw new BadRequestException(
                "Cannot cancel after a team member has been assigned. Please contact support.");
        }

        guardTransition(sr.getStatus(), ServiceRequestStatus.CANCELLED);
        closeRequest(sr, ServiceRequestStatus.CANCELLED,
            (reason != null && !reason.isBlank()) ? reason : "Cancelled by platform user",
            currentUser, requireCompanyId(), false);
    }

    @Override
    @Transactional
    public void systemCancelForNonPayment(Long id, long deadlineHours) {
        ServiceRequest sr = serviceRequestRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Service request not found: " + id));
        if (sr.isPermanentlyClosed() || TERMINAL_STATUSES.contains(sr.getStatus())) return;

        // actor null: a scheduled sweep has no signed-in user, and the history row is stamped "System" for it.
        closeRequest(sr, ServiceRequestStatus.CANCELLED,
            "Automatically cancelled - payment not received within " + deadlineHours + " hours",
            null, sr.getCompany().getId(), true);
    }

    /** The single cancellation/rejection path: closes permanently, records history, releases quota, cancels/refunds the invoice, notifies the client; explicit companyId so it works without a security context. */
    private void closeRequest(ServiceRequest sr, ServiceRequestStatus terminalStatus, String reason,
                              User actor, Long companyId, boolean nonPayment) {
        ServiceRequestStatus oldStatus = sr.getStatus();
        sr.setStatus(terminalStatus);
        sr.setPermanentlyClosed(true);
        sr.setSlaPausedAt(null);
        recordStatusChange(sr, oldStatus, terminalStatus, reason, actor, companyId);

        if (sr.getSubscription() != null) {
            packageService.releaseQuotaForCompany(companyId, sr.getSubscription().getId());
        }
        if (sr.getInvoiceId() != null) {
            invoiceService.cancelOrRefundForServiceRequest(companyId, sr.getInvoiceId());
        }

        // Tell the client - unless they closed it themselves.
        boolean clientIsActor = actor != null && sr.getClient() != null && sr.getClient().getUser() != null
            && sr.getClient().getUser().getId().equals(actor.getId());
        if (!clientIsActor) {
            try {
                notifyClientOnStatusChange(sr, terminalStatus);
            } catch (Exception ex) {
                log.warn("Close notification failed for service request {} (still {}): {}",
                    sr.getId(), terminalStatus, ex.getMessage());
            }
        }

        if (nonPayment && sr.getClient() != null && sr.getClient().getUser() != null) {
            try {
                Company fullCompany = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendServiceRequestCancelledEmail(
                    sr.getClient().getUser().getEmail(), sr.getClient().getUser().getFirstName(),
                    sr.getTitle(), branding);
            } catch (Exception ex) {
                log.warn("Cancellation email failed for service request {} (still cancelled): {}", sr.getId(), ex.getMessage());
            }
        }
    }

    @Override
    @Transactional
    public RequestCommentResponse addComment(Long requestId, AddCommentRequest request) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findInTenant(requestId);
        User currentUser = securityUtil.getCurrentUser();

        // Clients default to CLIENT-visible comments, staff default to INTERNAL.
        CommentVisibility defaultVisibility = isClientRole(currentUser)
                ? CommentVisibility.CLIENT : CommentVisibility.INTERNAL;
        // A client can never write a staff-only INTERNAL note, whatever visibility they send.
        CommentVisibility visibility = isClientRole(currentUser)
                ? CommentVisibility.CLIENT
                : (request.getVisibility() != null ? request.getVisibility() : defaultVisibility);

        RequestComment comment = RequestComment.builder()
            .content(request.getContent())
            .visibility(visibility)
            .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
            .serviceRequest(sr)
            .company(companyRef(companyId))
            .author(currentUser)
            .build();

        commentRepository.save(comment);
        RequestCommentResponse response = ServiceRequestMapper.toCommentResponse(comment);

        // Notify the OTHER side of the conversation, not the author (this used to notify the client even when the client wrote the comment).
        try {
            if (isClientRole(currentUser)) {
                Employee assigned = sr.getAssignedEmployee();
                if (assigned != null && assigned.getUser() != null) {
                    Long agentId = assigned.getUser().getId();
                    String clientLabel = sr.getClient() != null && sr.getClient().getClientCompanyName() != null
                        ? sr.getClient().getClientCompanyName() : currentUser.getFirstName();
                    notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                        NotificationType.REQUEST_UPDATED, "New Message",
                        clientLabel + " sent a message on \"" + sr.getTitle() + "\".",
                        agentId, companyId, requestId
                    ));
                    pushChatMessage(requestId, agentId, response);
                } else {
                    // Not assigned yet - alert whoever can pick it up, same as on initial submission.
                    List<Long> staffRecipients = notifyAssignableStaff(companyId, NotificationType.REQUEST_UPDATED,
                        "New Message", "A client sent a message on \"" + sr.getTitle() + "\".", requestId);
                    staffRecipients.forEach(id -> pushChatMessage(requestId, id, response));
                }
            } else if (comment.getVisibility() == CommentVisibility.CLIENT
                    && sr.getClient() != null && sr.getClient().getUser() != null) {
                Long clientUserId = sr.getClient().getUser().getId();
                notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                    NotificationType.REQUEST_UPDATED, "New Message",
                    "A new update has been added to your request \"" + sr.getTitle() + "\".",
                    clientUserId, companyId, requestId
                ));
                pushChatMessage(requestId, clientUserId, response);
            }
        } catch (Exception ex) {
            log.warn("Message notification failed for request {}: {}", requestId, ex.getMessage());
        }

        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public Page<RequestCommentResponse> getComments(Long requestId, Pageable pageable) {
        findInTenant(requestId);
        // findInTenant()'s guardAccess() only proves ownership; INTERNAL notes must still be filtered out for CLIENT callers here.
        User currentUser = securityUtil.getCurrentUser();
        Page<RequestComment> comments = isClientRole(currentUser)
            ? commentRepository.findByServiceRequestIdAndVisibilityOrderByCreatedAtDesc(
                requestId, CommentVisibility.CLIENT, pageable)
            : commentRepository.findByServiceRequestIdOrderByCreatedAtDesc(requestId, pageable);
        return comments.map(ServiceRequestMapper::toCommentResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<RequestStatusHistoryResponse> getStatusHistory(Long requestId) {
        findInTenant(requestId);
        return historyRepository
            .findByServiceRequestIdOrderByChangedAtAsc(requestId)
            .stream().map(ServiceRequestMapper::toHistoryResponse).toList();
    }

    /*
     * Deliberately NOT @Transactional, and nothing here nests: the approval gate used to run a REQUIRES_NEW
     * TransactionTemplate inside this method's own transaction, so every advance held two pooled connections at
     * once and the pool starved under concurrency. The gate now runs as its own transaction that COMMITS before
     * the advance transaction starts, so one request needs one connection at a time. Behaviour is unchanged: the
     * pending approval row still survives the BadRequestException thrown right after it, because that exception
     * is raised after the gate transaction has committed rather than inside it.
     *
     * Both callers (the controller and StageApprovalServiceImpl.approve(), itself non-transactional) invoke this
     * with no transaction in progress, so the two steps below really are separate transactions.
     */
    @Override
    public ServiceRequestResponse advanceStage(Long id) {
        String stageAwaitingApproval = newTransaction().execute(status -> reserveStageApproval(id));
        if (stageAwaitingApproval != null) {
            throw new BadRequestException("Stage \"" + stageAwaitingApproval
                + "\" requires approval. An approval request is pending in the approvals queue.");
        }
        return newTransaction().execute(status -> applyStageAdvance(id));
    }

    private org.springframework.transaction.support.TransactionTemplate newTransaction() {
        return new org.springframework.transaction.support.TransactionTemplate(transactionManager);
    }

    /**
     * Step 1, in its own committing transaction: validates the advance and, when the next stage needs an approval
     * that isn't granted yet, records the pending approval and returns the stage name so the caller can refuse.
     * Returns null when the advance may proceed. Validation failures throw here and roll back, writing nothing.
     */
    private String reserveStageApproval(Long id) {
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        List<WorkflowStage> stages = loadWorkflowStages(sr);
        int current = sr.getCurrentStage() != null ? sr.getCurrentStage() : 0;
        if (current >= stages.size()) {
            throw new BadRequestException("Request is already at the final workflow stage");
        }

        WorkflowStage next = stages.get(current); // currentStage counts completed stages
        if (!Boolean.TRUE.equals(next.getRequiresApproval())
            || stageApprovalRepository.existsByServiceRequestIdAndWorkflowStageIdAndStatus(
                sr.getId(), next.getId(), ApprovalStatus.APPROVED)) {
            return null;
        }

        boolean alreadyPending = stageApprovalRepository
            .existsByServiceRequestIdAndWorkflowStageIdAndStatus(sr.getId(), next.getId(), ApprovalStatus.PENDING);
        if (!alreadyPending) {
            stageApprovalRepository.save(StageApproval.builder()
                .serviceRequest(sr)
                .workflowStage(next)
                .approverRole(next.getAssigneeRole())
                .requestedBy(securityUtil.getCurrentUser())
                .company(sr.getCompany())
                .build());
        }
        return next.getName();
    }

    /** Step 2, in its own transaction: performs the advance. Re-validates, since step 1 committed and released its lock. */
    private ServiceRequestResponse applyStageAdvance(Long id) {
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        List<WorkflowStage> stages = loadWorkflowStages(sr);
        int current = sr.getCurrentStage() != null ? sr.getCurrentStage() : 0;
        if (current >= stages.size()) {
            throw new BadRequestException("Request is already at the final workflow stage");
        }

        WorkflowStage next = stages.get(current); // currentStage counts completed stages
        // Step 1 cleared this gate; re-checked in case the approval was revoked in between. No write here, so
        // this transaction stays clean to roll back.
        if (Boolean.TRUE.equals(next.getRequiresApproval())
            && !stageApprovalRepository.existsByServiceRequestIdAndWorkflowStageIdAndStatus(
                sr.getId(), next.getId(), ApprovalStatus.APPROVED)) {
            throw new BadRequestException("Stage \"" + next.getName()
                + "\" requires approval. An approval request is pending in the approvals queue.");
        }

        sr.setCurrentStage(current + 1);

        // Stage SLA refreshes the deadline; slaBreach describes only the CURRENT deadline, so it is cleared while firstBreachedAt/breachCount keep the history.
        if (next.getSlaHours() != null && next.getSlaHours() > 0) {
            // Deadline already missed but the 30-min breach sweep hasn't caught it - record it before the deadline is replaced.
            if (!sr.isSlaBreach() && sr.getSlaPausedAt() == null && sr.getSlaDeadline() != null
                    && sr.getSlaDeadline().isBefore(LocalDateTime.now())) {
                sr.markSlaBreached(LocalDateTime.now());
            }
            sr.setSlaHours(next.getSlaHours());
            sr.setSlaDeadline(LocalDateTime.now().plusHours(next.getSlaHours()));
            sr.setSlaBreach(false);
            // Re-stamp the pause so pause time accrued before the new deadline isn't added to it on resume.
            if (sr.getSlaPausedAt() != null) {
                sr.setSlaPausedAt(LocalDateTime.now());
            }
        }

        if (sr.getAssignedEmployee() != null && sr.getAssignedEmployee().getUser() != null) {
            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                NotificationType.REQUEST_UPDATED,
                "Request moved to stage: " + next.getName(),
                "Request \"" + sr.getTitle() + "\" advanced to stage \"" + next.getName() + "\"",
                sr.getAssignedEmployee().getUser().getId(),
                requireCompanyId(),
                sr.getId()));
        }

        // Milestone billing only notifies and posts the amount; collection stays manual because agreedPrice may not be set yet.
        if (Boolean.TRUE.equals(next.getRequiresPayment())
                && sr.getClient() != null && sr.getClient().getUser() != null) {
            String amountText;
            if (sr.getAgreedPrice() != null && next.getPaymentPercent() != null) {
                java.math.BigDecimal milestoneAmount = sr.getAgreedPrice()
                    .multiply(java.math.BigDecimal.valueOf(next.getPaymentPercent()))
                    .divide(java.math.BigDecimal.valueOf(100), 2, java.math.RoundingMode.HALF_UP);
                amountText = next.getPaymentPercent() + "% (" + milestoneAmount + ")";
            } else if (next.getPaymentPercent() != null) {
                amountText = next.getPaymentPercent() + "%";
            } else {
                amountText = "the next installment";
            }

            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                NotificationType.PAYMENT_DUE,
                "Milestone payment due",
                "\"" + next.getName() + "\" is complete - " + amountText
                    + " payment is now due for \"" + sr.getTitle() + "\".",
                sr.getClient().getUser().getId(),
                requireCompanyId(),
                sr.getId()));

            commentRepository.save(RequestComment.builder()
                .content("Milestone reached: \"" + next.getName() + "\" is complete. "
                    + amountText + " payment is now due.")
                .visibility(CommentVisibility.CLIENT)
                .serviceRequest(sr)
                .company(sr.getCompany())
                .author(securityUtil.getCurrentUser())
                .build());
        }

        return toResponse(sr);
    }

    @Override
    @Transactional(readOnly = true)
    public StageProgressResponse getStageProgress(Long id) {
        ServiceRequest sr = findInTenant(id);
        List<WorkflowStage> stages = loadWorkflowStages(sr);
        int current = sr.getCurrentStage() != null ? sr.getCurrentStage() : 0;

        StageProgressResponse response = new StageProgressResponse();
        response.setServiceRequestId(sr.getId());
        response.setCurrentStage(current);
        response.setTotalStages(stages.size());
        response.setStages(stages.stream().map(stage -> {
            StageProgressResponse.StageItem item = new StageProgressResponse.StageItem();
            item.setStageId(stage.getId());
            item.setName(stage.getName());
            item.setStageOrder(stage.getStageOrder());
            item.setSlaHours(stage.getSlaHours());
            item.setRequiresApproval(stage.getRequiresApproval());
            item.setRequiresPayment(stage.getRequiresPayment());
            item.setPaymentPercent(stage.getPaymentPercent());
            int index = stages.indexOf(stage);
            item.setCompleted(index < current);
            item.setCurrent(index == current);
            if (Boolean.TRUE.equals(stage.getRequiresApproval())) {
                item.setApprovalStatus(resolveApprovalStatus(sr.getId(), stage.getId()));
            }
            return item;
        }).toList());
        return response;
    }

    private List<WorkflowStage> loadWorkflowStages(ServiceRequest sr) {
        if (sr.getCompanyService() == null || sr.getCompanyService().getWorkflowTemplate() == null) {
            throw new BadRequestException("This service has no workflow template configured");
        }
        List<WorkflowStage> stages = workflowStageRepository
            .findByWorkflowTemplateIdOrderByStageOrderAsc(sr.getCompanyService().getWorkflowTemplate().getId());
        if (stages.isEmpty()) {
            throw new BadRequestException("The workflow template has no stages configured");
        }
        return stages;
    }

    private String resolveApprovalStatus(Long serviceRequestId, Long stageId) {
        for (ApprovalStatus status : List.of(ApprovalStatus.APPROVED, ApprovalStatus.PENDING, ApprovalStatus.REJECTED)) {
            if (stageApprovalRepository.existsByServiceRequestIdAndWorkflowStageIdAndStatus(serviceRequestId, stageId, status)) {
                return status.name();
            }
        }
        return null;
    }

    // aiTx.load() commits reads before the provider call so no DB connection is held across it - see AiTransactionBoundary; all lazy associations are read inside the callback.
    @Override
    public ServiceRequestResponse summarise(Long id) {
        PreparedPrompt<ServiceRequestResponse> prepared = aiTx.load(() -> {
            ServiceRequest sr = findInTenant(id);
            ServiceRequestResponse dto = toResponse(sr);

            long taskCount = taskRepository.countByServiceRequestId(sr.getId());
            long completedCount = taskRepository.countByServiceRequestIdAndStatus(sr.getId(), TaskStatus.COMPLETED);
            String recentComments = commentRepository
                .findByServiceRequestIdOrderByCreatedAtDesc(sr.getId(), PageRequest.of(0, 5))
                .stream()
                .map(RequestComment::getContent)
                .reduce((a, b) -> a + "\n- " + b)
                .map(joined -> "- " + joined)
                .orElse(null);

            return new PreparedPrompt<>(dto, ServiceRequestSummaryPromptBuilder.builder()
                .setTitle(sr.getTitle())
                .setDescription(sr.getDescription())
                .setStatus(sr.getStatus().name())
                .setPriority(sr.getPriority() != null ? sr.getPriority().name() : "NORMAL")
                .setClientName(sr.getClient() != null ? sr.getClient().getClientCompanyName() : null)
                .setAssignedEmployeeName(sr.getAssignedEmployee() != null && sr.getAssignedEmployee().getUser() != null
                    ? sr.getAssignedEmployee().getUser().getFullName() : null)
                .setTaskProgress(completedCount + " of " + taskCount + " tasks completed")
                .setSlaBreach(sr.isSlaBreach())
                .setRecentComments(recentComments)
                .build());
        });

        ServiceRequestResponse response = prepared.payload();
        response.setAiSummary(aiService.generateRaw(AiFeature.SERVICE_REQUEST_SUMMARY, prepared.prompt()));
        return response;
    }

    // Same aiTx.load() pattern as summarise(); tagged under SERVICE_REQUEST_SUMMARY deliberately so audit groups both.
    @Override
    public ServiceRequestReplyDraftResponse draftReply(Long id, ServiceRequestReplyDraftRequest request) {
        PreparedPrompt<Void> prepared = aiTx.load(() -> {
            ServiceRequest sr = findInTenant(id);

            // Client-visible comments only: the draft is sent to the client, so INTERNAL notes must not leak into it or reach the AI provider.
            String recentComments = commentRepository
                .findByServiceRequestIdAndVisibilityOrderByCreatedAtDesc(
                    sr.getId(), com.zuhoocms.enums.CommentVisibility.CLIENT, PageRequest.of(0, 5))
                .stream()
                .map(RequestComment::getContent)
                .reduce((a, b) -> a + "\n- " + b)
                .map(joined -> "- " + joined)
                .orElse(null);

            return new PreparedPrompt<>(null, ServiceRequestReplyDraftPromptBuilder.builder()
                .setTitle(sr.getTitle())
                .setStatus(sr.getStatus().name())
                .setRecentComments(recentComments)
                .setRoughNotes(request.getRoughNotes())
                .build());
        });

        String reply = aiService.generateRaw(AiFeature.SERVICE_REQUEST_SUMMARY, prepared.prompt());
        return new ServiceRequestReplyDraftResponse(reply.trim());
    }

    /** Notifies the company owner plus active employees whose CustomRole holds SERVICE_REQUEST_ASSIGN, and returns their user ids so callers can push live chat to the same people. */
    private List<Long> notifyAssignableStaff(Long companyId, NotificationType type, String title,
                                              String message, Long requestId) {
        List<Long> recipients = new ArrayList<>();
        Company company = companyRepository.findById(companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
        Long ownerId = company.getOwner() != null ? company.getOwner().getId() : null;

        if (ownerId != null) {
            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                type, title, message, ownerId, companyId, requestId));
            recipients.add(ownerId);
        }

        for (Employee employee : employeeRepository.findByCompanyIdAndActiveTrue(companyId)) {
            User employeeUser = employee.getUser();
            if (employeeUser == null || employeeUser.getId().equals(ownerId)
                    || employeeUser.getCustomRole() == null) {
                continue;
            }
            boolean canAssign = rolePermissionRepository.existsByCustomRoleIdAndPermission_Code(
                employeeUser.getCustomRole().getId(), PermissionCode.SERVICE_REQUEST_ASSIGN.name());
            if (canAssign) {
                notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                    type, title, message, employeeUser.getId(), companyId, requestId));
                recipients.add(employeeUser.getId());
            }
        }
        return recipients;
    }

    /** Pushes to each recipient's personal queue instead of the 60s bell poll; convertAndSendToUser (not a public /topic) keeps one client's ticket off another client's socket. */
    private void pushChatMessage(Long requestId, Long recipientUserId, RequestCommentResponse message) {
        try {
            messagingTemplate.convertAndSendToUser(
                recipientUserId.toString(), "/queue/service-requests/" + requestId + "/messages", message);
        } catch (Exception ex) {
            log.debug("Live chat push failed for user {} on request {}: {}", recipientUserId, requestId, ex.getMessage());
        }
    }

    static final List<ServiceRequestStatus> TERMINAL_STATUSES = List.of(
        ServiceRequestStatus.COMPLETED, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED);

    /** Legal manual transitions for changeStatus()/cancel(); quotation endpoints move PENDING &lt;-&gt; QUOTATION_PENDING on their own. */
    private static final Map<ServiceRequestStatus, java.util.Set<ServiceRequestStatus>> ALLOWED_TRANSITIONS;
    static {
        Map<ServiceRequestStatus, java.util.Set<ServiceRequestStatus>> m = new java.util.EnumMap<>(ServiceRequestStatus.class);
        m.put(ServiceRequestStatus.PENDING, java.util.EnumSet.of(
            ServiceRequestStatus.QUOTATION_PENDING, ServiceRequestStatus.ASSIGNED, ServiceRequestStatus.IN_PROGRESS,
            ServiceRequestStatus.WAITING_CLIENT, ServiceRequestStatus.UNDER_REVIEW,
            ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.QUOTATION_PENDING, java.util.EnumSet.of(
            ServiceRequestStatus.PENDING, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.ASSIGNED, java.util.EnumSet.of(
            ServiceRequestStatus.PENDING, ServiceRequestStatus.IN_PROGRESS, ServiceRequestStatus.WAITING_CLIENT,
            ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.IN_PROGRESS, java.util.EnumSet.of(
            ServiceRequestStatus.WAITING_CLIENT, ServiceRequestStatus.UNDER_REVIEW,
            ServiceRequestStatus.COMPLETED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.WAITING_CLIENT, java.util.EnumSet.of(
            ServiceRequestStatus.ASSIGNED, ServiceRequestStatus.IN_PROGRESS, ServiceRequestStatus.UNDER_REVIEW,
            ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.UNDER_REVIEW, java.util.EnumSet.of(
            ServiceRequestStatus.IN_PROGRESS, ServiceRequestStatus.WAITING_CLIENT,
            ServiceRequestStatus.COMPLETED, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.RESUBMITTED, java.util.EnumSet.of(
            ServiceRequestStatus.PENDING, ServiceRequestStatus.ASSIGNED, ServiceRequestStatus.IN_PROGRESS,
            ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED));
        m.put(ServiceRequestStatus.COMPLETED, java.util.EnumSet.noneOf(ServiceRequestStatus.class));
        m.put(ServiceRequestStatus.REJECTED, java.util.EnumSet.noneOf(ServiceRequestStatus.class));
        m.put(ServiceRequestStatus.CANCELLED, java.util.EnumSet.noneOf(ServiceRequestStatus.class));
        ALLOWED_TRANSITIONS = java.util.Collections.unmodifiableMap(m);
    }

    private void guardTransition(ServiceRequestStatus from, ServiceRequestStatus to) {
        if (to == null) {
            throw new BadRequestException("Target status is required");
        }
        java.util.Set<ServiceRequestStatus> allowed = ALLOWED_TRANSITIONS.getOrDefault(from, java.util.Set.of());
        if (!allowed.contains(to)) {
            String allowedText = allowed.isEmpty()
                ? "none - " + from + " is a final status"
                : allowed.stream().map(Enum::name).sorted().collect(java.util.stream.Collectors.joining(", "));
            throw new BadRequestException("Cannot change status from " + from + " to " + to
                + ". Allowed from " + from + ": " + allowedText);
        }
    }

    /** WAITING_CLIENT pauses the SLA clock: entering stamps slaPausedAt, leaving pushes the deadline out by the waited time. */
    private void applySlaPause(ServiceRequest sr, ServiceRequestStatus from, ServiceRequestStatus to) {
        LocalDateTime now = LocalDateTime.now();
        if (to == ServiceRequestStatus.WAITING_CLIENT && from != ServiceRequestStatus.WAITING_CLIENT) {
            if (sr.getSlaPausedAt() == null && sr.getSlaDeadline() != null && !sr.isSlaBreach()) {
                sr.setSlaPausedAt(now);
            }
        } else if (from == ServiceRequestStatus.WAITING_CLIENT && to != ServiceRequestStatus.WAITING_CLIENT) {
            if (sr.getSlaPausedAt() != null) {
                if (sr.getSlaDeadline() != null) {
                    sr.setSlaDeadline(sr.getSlaDeadline().plus(java.time.Duration.between(sr.getSlaPausedAt(), now)));
                }
                sr.setSlaPausedAt(null);
            }
        }
    }

    /** First workflow stage's slaHours when configured, else a default by priority. */
    private int computeInitialSlaHours(CompanyService service, ServiceRequestPriority priority) {
        if (service.getWorkflowTemplate() != null) {
            List<WorkflowStage> stages = workflowStageRepository
                .findByWorkflowTemplateIdOrderByStageOrderAsc(service.getWorkflowTemplate().getId());
            if (!stages.isEmpty() && stages.get(0).getSlaHours() != null && stages.get(0).getSlaHours() > 0) {
                return stages.get(0).getSlaHours();
            }
        }
        if (priority == null) return 72;
        return switch (priority) {
            case URGENT -> 8;
            case HIGH -> 24;
            case NORMAL -> 72;
            case LOW -> 168;
        };
    }

    /** Published after commit so async usage billing never runs for a completion that rolls back or reads the request before COMPLETED is visible. */
    private void publishCompletedAfterCommit(Long companyId, Long requestId, Long clientId) {
        if (org.springframework.transaction.support.TransactionSynchronizationManager.isSynchronizationActive()) {
            org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(
                new org.springframework.transaction.support.TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        automationEventPublisher.publishServiceRequestCompleted(
                            ServiceRequestServiceImpl.this, companyId, requestId, clientId);
                    }
                });
        } else {
            automationEventPublisher.publishServiceRequestCompleted(this, companyId, requestId, clientId);
        }
    }

    private ServiceRequest findInTenant(Long id) {
        ServiceRequest sr = serviceRequestRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service request not found: " + id));
        guardAccess(sr);
        return sr;
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

    private void guardNotClosed(ServiceRequest sr) {
        if (sr.isPermanentlyClosed())
            throw new BadRequestException("This request is permanently closed");
    }

    /** Only CLIENT is restricted to their own requests: listAll() already exposes the whole company queue to staff, who must be able to triage unassigned requests. */
    private void guardAccess(ServiceRequest sr) {
        User user = securityUtil.getCurrentUser();
        if (user == null || user.getRole() == null) return;

        String role = user.getRole().name();
        if (!role.equals("CLIENT")) return;

        boolean isOwner = sr.getClient() != null
                && sr.getClient().getUser() != null
                && sr.getClient().getUser().getId().equals(user.getId());

        if (!isOwner) {
            throw new ForbiddenException("You do not have permission to access this service request");
        }
    }

    private void recordStatusChange(ServiceRequest sr, ServiceRequestStatus oldStatus,
                                     ServiceRequestStatus newStatus, String reason,
                                     User changedBy, Long companyId) {
        // changedBy is null for the scheduler's own cancellations; the row is then stamped "System" so the timeline
        // names an actor either way.
        historyRepository.save(RequestStatusHistory.builder()
            .serviceRequest(sr)
            .oldStatus(oldStatus)
            .newStatus(newStatus)
            .reason(reason)
            .changedBy(changedBy)
            .changedByName(changedBy != null ? changedBy.getFullName() : RequestStatusHistory.SYSTEM_ACTOR_NAME)
            .companyId(companyId)
            .build());
    }

    private void notifyClientOnStatusChange(ServiceRequest sr,
                                             ServiceRequestStatus newStatus) {
        if (sr.getClient() == null || sr.getClient().getUser() == null) return;
        NotificationType type = switch (newStatus) {
            case COMPLETED      -> NotificationType.COMPLETED;
            case REJECTED       -> NotificationType.REJECTED;
            case CANCELLED      -> NotificationType.CANCELLED;
            case IN_PROGRESS    -> NotificationType.REQUEST_UPDATED;
            case WAITING_CLIENT -> NotificationType.REQUEST_UPDATED;
            default             -> null;
        };
        if (type == null) return;
        notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
            type, "Request Update",
            "Your request \"" + sr.getTitle() + "\" is now "
                + newStatus.name().replace('_', ' ') + ".",
            sr.getClient().getUser().getId(),
            sr.getCompany().getId(),
            sr.getId()
        ));

        if (newStatus == ServiceRequestStatus.COMPLETED) {
            try {
                Company fullCompany = companyRepository.findById(sr.getCompany().getId())
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendTicketResolvedEmail(sr.getClient().getUser().getEmail(), sr.getClient().getUser().getFirstName(), sr.getTitle(), branding);
            } catch (Exception ex) {
                log.warn("Ticket resolved email failed for client {}: {}", sr.getClient().getUser().getEmail(), ex.getMessage());
            }
        }
    }

    private ServiceRequestResponse toResponse(ServiceRequest sr) {
        long taskCount = taskRepository.countByServiceRequestId(sr.getId());
        long completedCount = taskRepository.countByServiceRequestIdAndStatus(
            sr.getId(), TaskStatus.COMPLETED);
        ServiceRequestResponse response = ServiceRequestMapper.toResponse(sr, taskCount, completedCount);
        if (sr.getFormDataJson() != null && !sr.getFormDataJson().isBlank()) {
            try {
                response.setFormData(objectMapper.readValue(
                    sr.getFormDataJson(), new TypeReference<Map<String, String>>() {}));
            } catch (Exception ex) {
                log.warn("Could not parse formDataJson for request {}: {}", sr.getId(), ex.getMessage());
            }
        }
        return response;
    }

    /** Validates required dynamic form fields and serializes answers to JSON, keyed by ServiceFormField id so renamed labels don't orphan data. */
    private String validateAndSerializeFormData(
            Long companyId, Long serviceId, Map<String, String> formData) {
        List<ServiceFormField> fields = serviceFormFieldRepository
            .findByCompanyIdAndServiceIdOrderBySortOrderAsc(companyId, serviceId)
            .stream()
            .filter(f -> !f.isDeleted())
            .toList();
        for (ServiceFormField field : fields) {
            String value = formData == null ? null : formData.get(String.valueOf(field.getId()));

            if (field.isRequired() && (value == null || value.isBlank())) {
                throw new BadRequestException("'" + field.getLabel() + "' is required");
            }
            
            if (value != null && !value.isBlank()) {
                FormFieldType type = field.getFieldType();
                if (type == FormFieldType.NUMBER) {
                    try {
                        new BigDecimal(value);
                    } catch (NumberFormatException e) {
                        throw new BadRequestException("'" + field.getLabel() + "' must be a valid number");
                    }
                } else if (type == FormFieldType.DATE) {
                    try {
                        java.time.LocalDate.parse(value);
                    } catch (java.time.format.DateTimeParseException e) {
                        throw new BadRequestException("'" + field.getLabel() + "' must be a valid date (YYYY-MM-DD)");
                    }
                } else if (type == FormFieldType.EMAIL) {
                    if (!value.matches("^[A-Za-z0-9+_.-]+@(.+)$")) {
                        throw new BadRequestException("'" + field.getLabel() + "' must be a valid email address");
                    }
                } else if (type == FormFieldType.PHONE) {
                    if (!value.matches("^\\+?[0-9\\s-]{7,15}$")) {
                        throw new BadRequestException("'" + field.getLabel() + "' must be a valid phone number");
                    }
                } else if (type == FormFieldType.FILE_UPLOAD) {
                    // Same rule as comment attachments: "starts with http" accepted any external URL, so a client could store a link to a file this app never held.
                    try {
                        com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(value);
                    } catch (BadRequestException ex) {
                        throw new BadRequestException("'" + field.getLabel() + "': " + ex.getMessage());
                    }
                }
            }
        }
        if (formData == null || formData.isEmpty()) return null;
        try {
            return objectMapper.writeValueAsString(formData);
        } catch (Exception ex) {
            throw new BadRequestException("Invalid form data");
        }
    }

    @Override
    @Transactional
    public ServiceRequestResponse submitQuotation(Long id, SubmitQuotationRequest request) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findInTenant(id);
        // Without these guards, submitting a quotation reopened COMPLETED/closed requests via QUOTATION_PENDING.
        guardNotClosed(sr);
        if (sr.getStatus() != ServiceRequestStatus.PENDING
                && sr.getStatus() != ServiceRequestStatus.QUOTATION_PENDING) {
            throw new BadRequestException("A quotation can only be submitted while the request is PENDING or "
                + "QUOTATION_PENDING (current status: " + sr.getStatus() + ")");
        }

        // Default to the service's currency, not the entity's hard-coded "USD", so the invoice is raised in the right currency.
        String currency = request.getCurrency() != null && !request.getCurrency().isBlank()
            ? request.getCurrency()
            : (sr.getCompanyService() != null ? sr.getCompanyService().getCurrency() : null);
        sr.submitQuotation(request.getAmount(), currency, request.getNotes(), request.getValidUntil());
        sr = serviceRequestRepository.save(sr);

        if (sr.getClient() != null && sr.getClient().getUser() != null) {
            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                NotificationType.REQUEST_UPDATED,
                "Quotation Ready",
                "A quotation of " + sr.getQuotationAmount() + " " + sr.getQuotationCurrency()
                    + " is ready for your review on \"" + sr.getTitle() + "\".",
                sr.getClient().getUser().getId(), companyId, id
            ));
        }

        return toResponse(sr);
    }

    @Override
    @Transactional
    public ServiceRequestResponse acceptQuotation(Long id) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        if (sr.getQuotationStatus() != com.zuhoocms.enums.QuotationStatus.PENDING) {
            throw new BadRequestException("Only pending quotations can be accepted.");
        }
        if (sr.getQuotationValidUntil() != null && LocalDateTime.now().isAfter(sr.getQuotationValidUntil())) {
            sr.setQuotationStatus(com.zuhoocms.enums.QuotationStatus.EXPIRED);
            serviceRequestRepository.save(sr);
            throw new BadRequestException("This quotation expired on " + sr.getQuotationValidUntil()
                + " and can no longer be accepted");
        }

        sr.acceptQuotation();
        sr = serviceRequestRepository.save(sr);

        notifyEmployeeOnQuotationDecision(sr, companyId, "accepted");

        ServiceRequestResponse response = toResponse(sr);

        if (sr.getAgreedPrice() != null && sr.getAgreedPrice().compareTo(BigDecimal.ZERO) > 0) {
            // Overwriting invoiceId orphaned any existing invoice - still owed, invisible to every cancel/refund path - so void or refund it first.
            if (sr.getInvoiceId() != null) {
                // VOIDED, not CANCELLED: the old invoice is replaced by the one raised below.
                invoiceService.voidSupersededForServiceRequest(companyId, sr.getInvoiceId());
            }

            ClientInvoiceItemRequest item = ClientInvoiceItemRequest.builder()
                .description("Service Request (Quotation Accepted): " + sr.getTitle())
                .quantity(new BigDecimal("1"))
                .unitPrice(sr.getAgreedPrice())
                .build();

            ClientInvoiceRequest invoiceRequest = ClientInvoiceRequest.builder()
                .clientId(sr.getClient().getId())
                .serviceRequestId(sr.getId())
                .invoiceDate(java.time.LocalDate.now())
                .dueDate(java.time.LocalDate.now().plusDays(3))
                .currency(sr.getQuotationCurrency())
                .notes("Invoice for Service Request: " + sr.getTitle())
                .items(List.of(item))
                .build();

            ClientInvoiceResponse invoiceResponse = invoiceService.createForServiceRequest(companyId, invoiceRequest);
            sr.setInvoiceId(invoiceResponse.getId());
            serviceRequestRepository.save(sr);
            response.setInvoiceId(invoiceResponse.getId());
            
            invoiceService.sendInvoiceForServiceRequest(invoiceResponse.getId());
        }
        
        return response;
    }

    @Override
    @Transactional
    public ServiceRequestResponse rejectQuotation(Long id, RejectQuotationRequest request) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findInTenant(id);
        guardNotClosed(sr);

        if (sr.getQuotationStatus() != com.zuhoocms.enums.QuotationStatus.PENDING) {
            throw new BadRequestException("Only pending quotations can be rejected.");
        }

        sr.rejectQuotation(request.getReason());
        sr = serviceRequestRepository.save(sr);

        notifyEmployeeOnQuotationDecision(sr, companyId, "rejected");

        return toResponse(sr);
    }

    private void notifyEmployeeOnQuotationDecision(ServiceRequest sr, Long companyId, String decision) {
        if (sr.getAssignedEmployee() == null || sr.getAssignedEmployee().getUser() == null) return;
        notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
            NotificationType.REQUEST_UPDATED,
            "Quotation " + decision.substring(0, 1).toUpperCase() + decision.substring(1),
            "The client " + decision + " the quotation for \"" + sr.getTitle() + "\".",
            sr.getAssignedEmployee().getUser().getId(), companyId, sr.getId()
        ));
    }

    /** Blocks ordering until the client has at least one COMPLETED request for each mandatory prerequisite service; in-progress or rejected attempts don't count. */
    private void validatePrerequisites(Long companyId, Long clientId, CompanyService service) {
        List<com.zuhoocms.modules.servicedesk.companyservice.ServicePrerequisite> prerequisites =
            servicePrerequisiteRepository.findByServiceIdOrderByIdAsc(service.getId());

        for (com.zuhoocms.modules.servicedesk.companyservice.ServicePrerequisite prereq : prerequisites) {
            if (!prereq.isMandatory()) continue;

            CompanyService prereqService = prereq.getPrerequisiteService();
            boolean satisfied = serviceRequestRepository.existsByCompanyIdAndClientIdAndCompanyServiceIdAndStatus(
                companyId, clientId, prereqService.getId(), ServiceRequestStatus.COMPLETED);

            if (!satisfied) {
                String message = prereq.getMessage() != null && !prereq.getMessage().isBlank()
                    ? prereq.getMessage()
                    : "'" + service.getName() + "' requires a completed '" + prereqService.getName() + "' first";
                throw new BadRequestException(message);
            }
        }
    }

    private void validateRequiredDocuments(ServiceRequest sr) {
        CompanyService service = sr.getCompanyService();
        if (service == null) return;
        
        Long companyId = sr.getCompany().getId();
        
        List<com.zuhoocms.modules.servicedesk.document.RequiredDocument> mandatoryDocs = requiredDocumentRepository
            .findByCompanyIdAndServiceIdOrderBySortOrderAsc(companyId, service.getId())
            .stream()
            .filter(com.zuhoocms.modules.servicedesk.document.RequiredDocument::isMandatory)
            .toList();
            
        if (mandatoryDocs.isEmpty()) return;
        
        List<com.zuhoocms.modules.servicedesk.document.Document> uploadedDocs = documentRepository
            .findByServiceRequestIdOrderByCreatedAtDesc(sr.getId());
        
        for (com.zuhoocms.modules.servicedesk.document.RequiredDocument reqDoc : mandatoryDocs) {
            boolean uploaded = uploadedDocs.stream()
                .anyMatch(doc -> doc.getLabel() != null && doc.getLabel().equalsIgnoreCase(reqDoc.getDocName().trim()));
            if (!uploaded) {
                throw new BadRequestException("Mandatory document '" + reqDoc.getDocName() + "' is missing");
            }
        }
    }

    private boolean isClientRole(User user) {
        return user != null && user.getRole() != null
                && user.getRole().name().equals("CLIENT");
    }
}
