package com.zuhoocms.modules.support.ticket;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.support.agent.SupportAgent;
import com.zuhoocms.modules.support.agent.SupportAgentRepository;
import com.zuhoocms.modules.support.agent.SupportAgentStatus;
import com.zuhoocms.modules.support.audit.SupportAuditLogRepository;
import com.zuhoocms.modules.support.category.SupportCategory;
import com.zuhoocms.modules.support.category.SupportCategoryRepository;
import com.zuhoocms.modules.support.sla.SLAPolicy;
import com.zuhoocms.modules.support.sla.SLAPolicyRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditLog;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;

@Slf4j
@Service
@RequiredArgsConstructor
public class SupportTicketServiceImpl implements SupportTicketService {

    private final SupportTicketRepository ticketRepository;
    private final SupportTicketNumberGenerator ticketNumberGenerator;
    private final SupportCategoryRepository categoryRepository;
    private final SupportAgentRepository agentRepository;
    private final SLAPolicyRepository slaPolicyRepository;
    private final SupportAuditLogRepository auditRepository;
    private final CompanyRepository companyRepository;
    private final UserRepository userRepository;
    private final ClientRepository clientRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final NotificationService notificationService;

    private static final List<TicketStatus> CLOSED_STATUSES = List.of(TicketStatus.RESOLVED, TicketStatus.CLOSED);

    /** sla-breached / critical-open return plain lists - cap them instead of loading every row. */
    private static final int LIST_LIMIT = 200;

    private static final int MAX_ESCALATION_LEVEL = 3;

    @Override
    @Transactional
    public SupportTicketResponse create(SupportTicketRequest request) {
        Long companyId = securityUtil.getCurrentCompanyId();
        Long currentUserId = securityUtil.getCurrentUser().getId();

        Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        User createdBy = userRepository.findById(currentUserId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        SupportCategory category = null;
        if (request.getCategoryId() != null) {
            category = categoryRepository.findById(request.getCategoryId())
                    .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        }

        String ticketNumber = ticketNumberGenerator.next();

        LocalDateTime now = LocalDateTime.now();
        SLAPolicy slaPolicy = activePolicyFor(request.getPriority());

        SupportTicket ticket = SupportTicket.builder()
                .companyId(companyId)
                .ticketNumber(ticketNumber)
                .company(company)
                .createdBy(createdBy)
                .title(request.getTitle())
                .description(request.getDescription())
                .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
                .attachmentFileName(request.getAttachmentFileName())
                .category(category)
                .status(TicketStatus.NEW)
                .priority(request.getPriority())
                .source(request.getSource())
                .firstResponseDeadline(slaPolicy != null ? now.plusHours(slaPolicy.getFirstResponseTimeHours()) : null)
                .resolutionDeadline(slaPolicy != null ? now.plusHours(slaPolicy.getResolutionTimeHours()) : null)
                .build();

        ticket = ticketRepository.save(ticket);

        logAudit(companyId, currentUserId, AuditAction.CREATE_TICKET, ticket.getId(),
                "Ticket created: " + ticketNumber, null);

        return SupportTicketMapper.toResponse(ticket);
    }

    /** CLIENT raises a CUSTOMER_SUPPORT ticket: no SupportAgent involved, it stays unassigned until company staff pick it up (create() is PLATFORM_SUPPORT only). */
    @Override
    @Transactional
    public SupportTicketResponse createForClient(SupportTicketRequest request) {
        Client client = resolveClientForCurrentUser();
        Long companyId = client.getCompany().getId();

        Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        String ticketNumber = ticketNumberGenerator.next();

        LocalDateTime now = LocalDateTime.now();
        SLAPolicy slaPolicy = activePolicyFor(request.getPriority());

        SupportTicket ticket = SupportTicket.builder()
                .companyId(companyId)
                .ticketNumber(ticketNumber)
                .ticketType(TicketType.CUSTOMER_SUPPORT)
                .company(company)
                .createdBy(client.getUser())
                .client(client)
                .title(request.getTitle())
                .description(request.getDescription())
                .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
                .attachmentFileName(request.getAttachmentFileName())
                .status(TicketStatus.NEW)
                .priority(request.getPriority())
                .source(request.getSource())
                .firstResponseDeadline(slaPolicy != null ? now.plusHours(slaPolicy.getFirstResponseTimeHours()) : null)
                .resolutionDeadline(slaPolicy != null ? now.plusHours(slaPolicy.getResolutionTimeHours()) : null)
                .build();

        ticket = ticketRepository.save(ticket);

        logAudit(companyId, client.getUser().getId(), AuditAction.CREATE_TICKET, ticket.getId(),
                "Customer support ticket created: " + ticketNumber, null);

        return SupportTicketMapper.toResponse(ticket);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getMyClientTickets(Pageable pageable) {
        Client client = resolveClientForCurrentUser();
        return ticketRepository.findByClientIdAndCompanyId(client.getId(), client.getCompany().getId(), pageable)
                .map(SupportTicketMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public SupportTicketResponse getClientTicketById(Long id) {
        Client client = resolveClientForCurrentUser();
        SupportTicket ticket = ticketRepository
                .findByIdAndClientIdAndCompanyId(id, client.getId(), client.getCompany().getId())
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        return SupportTicketMapper.toResponse(ticket);
    }

    /** Mirrors ServicePackageServiceImpl's client-resolution pattern. */
    private Client resolveClientForCurrentUser() {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            throw new BadRequestException("Not authenticated");
        }
        return clientRepository.findByUserId(current.getId())
                .orElseThrow(() -> new BadRequestException("No client profile linked to this account"));
    }

    @Override
    @Transactional(readOnly = true)
    public SupportTicketResponse getById(Long id) {
        return SupportTicketMapper.toResponse(findTicketForCaller(id));
    }

    /** Numbers generated before support_ticket_number_seq existed (count()+1) may be duplicated, so take the newest rather than 500. */
    @Override
    @Transactional(readOnly = true)
    public SupportTicketResponse getByTicketNumber(String number) {
        SupportTicket ticket = (isTenantCaller()
                ? ticketRepository.findFirstByTicketNumberAndCompanyIdOrderByIdDesc(number, securityUtil.getCurrentCompanyId())
                : ticketRepository.findFirstByTicketNumberOrderByIdDesc(number))
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        return SupportTicketMapper.toResponse(ticket);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getAll(Pageable pageable) {
        // Platform staff triage every company; a tenant caller (including an impersonating admin) is scoped to its own.
        if (isTenantCaller()) {
            authorizationService.checkPermission(PermissionCode.TICKET_VIEW);
            // Platform tickets only - CUSTOMER_SUPPORT has its own inbox, getClientTicketsForCompany().
            return ticketRepository.findByCompanyIdAndTicketType(
                    securityUtil.getCurrentCompanyId(), TicketType.PLATFORM_SUPPORT, pageable)
                    .map(SupportTicketMapper::toResponse);
        }
        return ticketRepository.findAll(pageable)
                .map(SupportTicketMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getByCompany(Long companyId, Pageable pageable) {
        Long effectiveCompanyId = isTenantCaller() ? securityUtil.getCurrentCompanyId() : companyId;
        return ticketRepository.findByCompanyId(effectiveCompanyId, pageable)
                .map(SupportTicketMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getByStatus(TicketStatus status, Pageable pageable) {
        if (isTenantCaller()) {
            authorizationService.checkPermission(PermissionCode.TICKET_VIEW);
            return ticketRepository.findByCompanyIdAndTicketTypeAndStatus(
                    securityUtil.getCurrentCompanyId(), TicketType.PLATFORM_SUPPORT, status, pageable)
                    .map(SupportTicketMapper::toResponse);
        }
        return ticketRepository.findByStatus(status, pageable)
                .map(SupportTicketMapper::toResponse);
    }

    /** Staff-facing counterpart to getAll(): this company's own clients' CUSTOMER_SUPPORT tickets. */
    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getClientTicketsForCompany(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.TICKET_VIEW);
        return ticketRepository.findByCompanyIdAndTicketType(
                securityUtil.getCurrentCompanyId(), TicketType.CUSTOMER_SUPPORT, pageable)
                .map(SupportTicketMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getClientTicketsForCompanyByStatus(TicketStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.TICKET_VIEW);
        return ticketRepository.findByCompanyIdAndTicketTypeAndStatus(
                securityUtil.getCurrentCompanyId(), TicketType.CUSTOMER_SUPPORT, status, pageable)
                .map(SupportTicketMapper::toResponse);
    }

    /** Client Chat detail: a platform ticket or another company's ticket 404s; matches servicedesk-service GET /company/client-tickets/{id}. */
    @Override
    @Transactional(readOnly = true)
    public SupportTicketResponse getClientTicketForCompany(Long id) {
        authorizationService.checkAnyPermission(PermissionCode.TICKET_VIEW, PermissionCode.SUPPORT_MESSAGE_VIEW);
        SupportTicket ticket = ticketRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .filter(t -> t.getTicketType() == TicketType.CUSTOMER_SUPPORT)
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        return SupportTicketMapper.toResponse(ticket);
    }

    /** Always the caller's own agent record - a client-supplied agentId is ignored. */
    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getAssignedToMe(Pageable pageable) {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            return Page.empty(pageable);
        }
        return agentRepository.findByUserId(current.getId())
                .map(agent -> ticketRepository.findByAssignedToAgentId(agent.getId(), pageable)
                        .map(SupportTicketMapper::toResponse))
                .orElseGet(() -> Page.empty(pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportTicketResponse> getMyTickets(Long userId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.TICKET_VIEW);
        Long targetUserId = userId != null ? userId : securityUtil.getCurrentUser().getId();
        // Company-scoped: a userId from another company must not list that company's tickets.
        return ticketRepository.findByCreatedByIdAndCompanyId(targetUserId, securityUtil.getCurrentCompanyId(), pageable)
                .map(SupportTicketMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportTicketResponse> getSLABreachedTickets() {
        PageRequest limit = PageRequest.of(0, LIST_LIMIT);
        LocalDateTime now = LocalDateTime.now();
        List<SupportTicket> tickets = isTenantCaller()
                ? ticketRepository.findSlaBreached(securityUtil.getCurrentCompanyId(), CLOSED_STATUSES, now, limit)
                : ticketRepository.findSlaBreached(CLOSED_STATUSES, now, limit);
        return tickets.stream().map(SupportTicketMapper::toResponse).toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportTicketResponse> getOpenCriticalTickets() {
        PageRequest limit = PageRequest.of(0, LIST_LIMIT);
        List<SupportTicket> tickets = isTenantCaller()
                ? ticketRepository.findOpenCritical(securityUtil.getCurrentCompanyId(), CLOSED_STATUSES, limit)
                : ticketRepository.findOpenCritical(CLOSED_STATUSES, limit);
        return tickets.stream().map(SupportTicketMapper::toResponse).toList();
    }

    @Override
    @Transactional
    public void assignToAgent(Long ticketId, Long agentId) {
        requireSupportStaff("assign tickets");
        SupportTicket ticket = lockTicketForCaller(ticketId);
        requireAssignable(ticket);

        SupportAgent agent = lockAgent(agentId);
        SupportAgent previous = ticket.getAssignedToAgent();
        if (previous != null && previous.getId().equals(agent.getId())) {
            return; // already assigned to this agent - nothing to do
        }
        requireAgentCapacity(agent);

        ticket.assignToAgent(agent);
        ticketRepository.save(ticket);

        String description = "Assigned to " + agentLabel(agent)
                + (previous != null ? " (previously " + agentLabel(previous) + ")" : "");
        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(),
                previous != null ? AuditAction.REASSIGN : AuditAction.ASSIGN, ticketId, description, null);
    }

    @Override
    @Transactional
    public void reassignToAgent(Long ticketId, Long newAgentId, String reason) {
        requireSupportStaff("reassign tickets");
        SupportTicket ticket = lockTicketForCaller(ticketId);
        requireAssignable(ticket);

        SupportAgent newAgent = lockAgent(newAgentId);
        SupportAgent oldAgent = ticket.getAssignedToAgent();
        if (oldAgent != null && oldAgent.getId().equals(newAgent.getId())) {
            throw new BadRequestException("Ticket is already assigned to " + agentLabel(newAgent));
        }
        requireAgentCapacity(newAgent);

        ticket.assignToAgent(newAgent);
        ticketRepository.save(ticket);

        String description = String.format("Reassigned from %s to %s. Reason: %s",
                oldAgent != null ? agentLabel(oldAgent) : "Unassigned", agentLabel(newAgent), reason);
        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.REASSIGN, ticketId,
                description, oldAgent != null ? "previousAgentId=" + oldAgent.getId() : null);
    }

    @Override
    @Transactional
    public void escalate(Long ticketId, String reason) {
        SupportTicket ticket = lockTicketForCaller(ticketId);
        if (!ticket.isActiveStatus()) {
            throw new BadRequestException("Only an open ticket can be escalated - this one is " + ticket.getStatus());
        }
        int level = ticket.getEscalationLevel() != null ? ticket.getEscalationLevel() : 1;
        if (level >= MAX_ESCALATION_LEVEL) {
            throw new BadRequestException("Ticket is already at the highest escalation level (" + MAX_ESCALATION_LEVEL + ")");
        }
        LocalDateTime now = LocalDateTime.now();
        if (isTenantCaller() && ticket.getEscalatedDate() != null
                && ticket.getEscalatedDate().isAfter(now.minusHours(24))) {
            throw new BadRequestException("This ticket was escalated less than 24 hours ago - it can be escalated again after "
                    + ticket.getEscalatedDate().plusHours(24).withNano(0));
        }

        ticket.setEscalationLevel(level + 1);
        ticket.setEscalatedDate(now);
        ticket.setEscalationReason(reason);
        ticketRepository.save(ticket);

        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.ESCALATE, ticketId,
                "Escalated to level " + ticket.getEscalationLevel() + ": " + reason, null);

        notifyEscalation(ticket, reason);
    }

    private void notifyEscalation(SupportTicket ticket, String reason) {
        try {
            String message = "Ticket " + ticket.getTicketNumber() + " was escalated to level "
                    + ticket.getEscalationLevel() + (reason != null ? ": " + reason : "");
            if (ticket.getTicketType() == TicketType.CUSTOMER_SUPPORT) {
                User owner = ticket.getCompany() != null ? ticket.getCompany().getOwner() : null;
                if (owner != null) {
                    notificationService.send(CreateNotificationRequest.of(NotificationType.GENERAL,
                            "Ticket escalated", message, "/support/client-chat", owner.getId(), ticket.getCompanyId()));
                }
                return;
            }
            for (User manager : userRepository.findByRoleIn(List.of(Role.SUPPORT_MANAGER), Pageable.unpaged())) {
                notificationService.send(CreateNotificationRequest.of(NotificationType.GENERAL,
                        "Ticket escalated", message, "/support/tickets/" + ticket.getId(),
                        manager.getId(), ticket.getCompanyId()));
            }
        } catch (RuntimeException ex) {
            log.warn("Escalation notification failed for ticket {}: {}", ticket.getId(), ex.getMessage());
        }
    }

    @Override
    @Transactional
    public void recordFirstResponse(Long ticketId) {
        SupportTicket ticket = lockTicketForCaller(ticketId);
        if (!ticket.isActiveStatus()) {
            throw new BadRequestException("Cannot record a first response on a " + ticket.getStatus() + " ticket");
        }
        if (ticket.getFirstResponseTime() != null) {
            throw new BadRequestException("First response was already recorded at " + ticket.getFirstResponseTime().withNano(0));
        }

        ticket.recordFirstResponse();
        if (ticket.getStatus() == TicketStatus.NEW || ticket.getStatus() == TicketStatus.OPEN
                || ticket.getStatus() == TicketStatus.REOPENED) {
            ticket.setStatus(TicketStatus.IN_PROGRESS);
        }
        ticketRepository.save(ticket);

        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.FIRST_RESPONSE, ticketId,
                "First response recorded", null);
    }

    @Override
    @Transactional
    public void resolve(Long ticketId, String resolutionNotes) {
        SupportTicket ticket = lockTicketForCaller(ticketId);
        requireOwnClientTicketIfTenant(ticket, "resolve");
        if (!ticket.isActiveStatus()) {
            throw new BadRequestException("Only an open ticket can be resolved - this one is " + ticket.getStatus());
        }
        if (resolutionNotes == null || resolutionNotes.isBlank()) {
            throw new BadRequestException("Resolution notes are required");
        }

        Long currentUserId = securityUtil.getCurrentUser().getId();
        User user = userRepository.findById(currentUserId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        ticket.resolve(resolutionNotes, user.getFullName());
        ticketRepository.save(ticket);

        logAudit(ticket.getCompanyId(), currentUserId, AuditAction.RESOLVE, ticketId, "Ticket resolved", null);
    }

    @Override
    @Transactional
    public void close(Long ticketId) {
        SupportTicket ticket = lockTicketForCaller(ticketId);
        requireOwnClientTicketIfTenant(ticket, "close");
        doClose(ticket);
    }

    private void doClose(SupportTicket ticket) {
        if (ticket.getStatus() != TicketStatus.RESOLVED) {
            throw new BadRequestException(
                    "Only a resolved ticket can be closed - resolve it first so the resolution is on record");
        }
        ticket.close();
        ticketRepository.save(ticket);

        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.CLOSE, ticket.getId(),
                "Ticket closed", null);
    }

    @Override
    @Transactional
    public void reopen(Long ticketId, String reason) {
        doReopen(lockTicketForCaller(ticketId), reason);
    }

    private void doReopen(SupportTicket ticket, String reason) {
        if (ticket.getStatus() != TicketStatus.RESOLVED && ticket.getStatus() != TicketStatus.CLOSED) {
            throw new BadRequestException("Only a resolved or closed ticket can be reopened - this one is " + ticket.getStatus());
        }
        // Restart the SLA clock from now for the ticket's current priority.
        LocalDateTime now = LocalDateTime.now();
        SLAPolicy policy = activePolicyFor(ticket.getPriority());
        ticket.reopen(
                policy != null ? now.plusHours(policy.getFirstResponseTimeHours()) : null,
                policy != null ? now.plusHours(policy.getResolutionTimeHours()) : null);
        ticketRepository.save(ticket);

        logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.REOPEN, ticket.getId(),
                "Ticket reopened: " + reason, null);
    }

    @Override
    @Transactional
    public void recordSatisfaction(Long ticketId, int rating, String feedback) {
        if (rating < 1 || rating > 5) {
            throw new BadRequestException("Rating must be between 1 and 5");
        }
        SupportTicket ticket = lockTicketForCaller(ticketId);
        User current = securityUtil.getCurrentUser();
        if (ticket.getCreatedBy() == null || current == null
                || !ticket.getCreatedBy().getId().equals(current.getId())) {
            throw new ForbiddenException("Only the person who raised this ticket can rate it");
        }
        if (ticket.getStatus() != TicketStatus.RESOLVED && ticket.getStatus() != TicketStatus.CLOSED) {
            throw new BadRequestException("A ticket can only be rated once it is resolved or closed");
        }

        ticket.setSatisfactionRating(rating);
        ticket.setSatisfactionFeedback(feedback);
        ticketRepository.save(ticket);
    }

    /** Applies only fields present in the request; a status change goes through the same guards as the action endpoints. */
    @Override
    @Transactional
    public SupportTicketResponse update(Long id, SupportTicketPatchRequest request) {
        SupportTicket ticket = lockTicketForCaller(id);

        boolean editsFields = request.getTitle() != null || request.getDescription() != null
                || request.getCategoryId() != null || request.getPriority() != null
                || request.getAttachmentUrl() != null || request.getAttachmentFileName() != null;
        if (editsFields && ticket.getStatus() == TicketStatus.CLOSED) {
            throw new BadRequestException("A closed ticket can't be edited - reopen it first");
        }

        if (request.getTitle() != null) {
            if (request.getTitle().isBlank()) throw new BadRequestException("Title cannot be blank");
            ticket.setTitle(request.getTitle());
        }
        if (request.getDescription() != null) {
            if (request.getDescription().isBlank()) throw new BadRequestException("Description cannot be blank");
            ticket.setDescription(request.getDescription());
        }
        if (request.getCategoryId() != null) {
            SupportCategory category = categoryRepository.findById(request.getCategoryId())
                    .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
            ticket.setCategory(category);
        }
        if (request.getAttachmentUrl() != null) ticket.setAttachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl(), ticket.getAttachmentUrl()));
        if (request.getAttachmentFileName() != null) ticket.setAttachmentFileName(request.getAttachmentFileName());

        if (request.getPriority() != null && request.getPriority() != ticket.getPriority()) {
            ticket.setPriority(request.getPriority());
            recomputeDeadlinesForPriority(ticket);
        }

        if (request.getStatus() != null && request.getStatus() != ticket.getStatus()) {
            applyStatusChange(ticket, request.getStatus());
        }

        ticket = ticketRepository.save(ticket);
        return SupportTicketMapper.toResponse(ticket);
    }

    private void applyStatusChange(SupportTicket ticket, TicketStatus target) {
        if (isTenantCaller() && ticket.getTicketType() != TicketType.CUSTOMER_SUPPORT) {
            throw new ForbiddenException("Only support staff can change the status of a platform support ticket");
        }
        switch (target) {
            case RESOLVED -> throw new BadRequestException(
                    "Use the resolve action to resolve a ticket - resolution notes are required");
            case CLOSED -> doClose(ticket);
            case REOPENED -> doReopen(ticket, "status changed to REOPENED");
            case NEW -> throw new BadRequestException("A ticket can't be moved back to NEW");
            default -> {
                if (!ticket.isActiveStatus()) {
                    throw new BadRequestException("A " + ticket.getStatus() + " ticket must be reopened before its status can change to " + target);
                }
                TicketStatus from = ticket.getStatus();
                ticket.setStatus(target);
                logAudit(ticket.getCompanyId(), securityUtil.getCurrentUser().getId(), AuditAction.UPDATE, ticket.getId(),
                        "Status changed from " + from + " to " + target, null);
            }
        }
    }

    /** Deadlines follow the new priority's SLA measured from when the ticket was raised; breach flags clear if the new deadline hasn't passed. */
    private void recomputeDeadlinesForPriority(SupportTicket ticket) {
        SLAPolicy policy = activePolicyFor(ticket.getPriority());
        LocalDateTime start = ticket.getCreatedAt() != null ? ticket.getCreatedAt() : LocalDateTime.now();
        LocalDateTime now = LocalDateTime.now();
        if (policy == null) {
            ticket.setFirstResponseDeadline(null);
            ticket.setResolutionDeadline(null);
        } else {
            ticket.setFirstResponseDeadline(start.plusHours(policy.getFirstResponseTimeHours()));
            ticket.setResolutionDeadline(start.plusHours(policy.getResolutionTimeHours()));
        }
        if (ticket.getResolutionDeadline() == null || ticket.getResolutionDeadline().isAfter(now)) {
            ticket.setSlaBreached(false);
        }
        if (ticket.getFirstResponseDeadline() == null || ticket.getFirstResponseDeadline().isAfter(now)) {
            ticket.setFirstResponseBreached(false);
        }
        if (!ticket.isSlaBreached() && !ticket.isFirstResponseBreached()) {
            ticket.setSlaBreachReason(null);
        }
    }

    @Override
    @Transactional
    public void delete(Long id) {
        SupportTicket ticket = lockTicketForCaller(id);
        ticket.softDelete();
        ticketRepository.save(ticket);
    }

    /** Tenant = effective role is a company role (includes an impersonating platform admin). */
    private boolean isTenantCaller() {
        User current = securityUtil.getCurrentUser();
        return current != null && !current.isPlatformUser();
    }

    /**
     * A company's own staff may close out a CUSTOMER_SUPPORT ticket - their client asking them for help, the
     * "Client Chat" screen. Until now resolve and close admitted only the PLATFORM's support roles, which no tenant
     * can hold, so a company could never finish its own customer's ticket by any route and the queue only grew.
     * Rating was stuck behind the same dead end, because only a RESOLVED or CLOSED ticket can be rated.
     *
     * Two things this deliberately does NOT open. A tenant still cannot touch a PLATFORM_SUPPORT ticket - the one
     * their company raised with us - because resolving your own request to your supplier is not a thing to grant;
     * the type check below is the whole of that rule, and lockTicketForCaller has already confined a tenant caller
     * to their own company. And platform staff keep their existing reach over both kinds.
     *
     * Gated on SUPPORT_MESSAGE_VIEW, which is the code that already governs staff working a client's ticket
     * (replyToClientTicket and getClientTicketMessagesForCompany both use it): anyone who may answer the client may
     * also mark the answer done. That needs no new code granting, which is what makes this work for existing roles.
     */
    private void requireOwnClientTicketIfTenant(SupportTicket ticket, String action) {
        if (!isTenantCaller()) {
            return;
        }
        if (ticket.getTicketType() != TicketType.CUSTOMER_SUPPORT) {
            throw new ForbiddenException("Only platform support staff can " + action + " this ticket");
        }
        authorizationService.checkPermission(PermissionCode.SUPPORT_MESSAGE_VIEW);
    }

    private void requireSupportStaff(String action) {
        User current = securityUtil.getCurrentUser();
        if (current == null || !current.isPlatformUser()) {
            throw new ForbiddenException("Only platform support staff can " + action);
        }
    }

    /** Only PLATFORM_SUPPORT tickets that are still being worked can take a SupportAgent. */
    private void requireAssignable(SupportTicket ticket) {
        if (!ticket.isActiveStatus()) {
            throw new BadRequestException("Cannot assign a " + ticket.getStatus() + " ticket - reopen it first");
        }
        if (ticket.getTicketType() == TicketType.CUSTOMER_SUPPORT) {
            throw new BadRequestException("Customer support tickets are handled by the company's own staff, not platform agents");
        }
    }

    /** Locks the agent row so concurrent assignments can't both slip under maxConcurrentTickets. */
    private SupportAgent lockAgent(Long agentId) {
        return agentRepository.lockById(agentId)
                .orElseThrow(() -> new ResourceNotFoundException("Agent not found"));
    }

    // SupportAgent has no company_id (support staff are platform-wide, not tenant-scoped).
    private void requireAgentCapacity(SupportAgent agent) {
        if (agent.getStatus() != SupportAgentStatus.ACTIVE) {
            throw new BadRequestException("Cannot assign to " + agentLabel(agent) + " - they are not an active agent");
        }
        if (!agent.isAcceptingTickets()) {
            throw new BadRequestException("Cannot assign to " + agentLabel(agent) + " - they are not accepting tickets");
        }
        long openCount = ticketRepository.countByAssignedToAgentIdAndStatusNotIn(agent.getId(), CLOSED_STATUSES);
        if (openCount >= agent.getMaxConcurrentTickets()) {
            throw new BadRequestException("Cannot assign to " + agentLabel(agent) + " - they already have "
                    + openCount + " open ticket(s), at their limit of " + agent.getMaxConcurrentTickets());
        }
    }

    private static String agentLabel(SupportAgent agent) {
        String name = agent.getUser() != null ? agent.getUser().getFullName() : "agent";
        return name + " (agent #" + agent.getId() + ")";
    }

    /** Tolerates legacy duplicate active policies for one priority - newest wins. */
    private SLAPolicy activePolicyFor(TicketPriority priority) {
        if (priority == null) return null;
        return slaPolicyRepository.findFirstByApplicablePriorityAndActiveTrueOrderByIdDesc(priority).orElse(null);
    }

    /** Read path: tenant callers (including an impersonating admin) are scoped to their own company, platform staff to every company. */
    private SupportTicket findTicketForCaller(Long id) {
        if (isTenantCaller()) {
            return ticketRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                    .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        }
        return ticketRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
    }

    /** Write path: same scoping as findTicketForCaller(), with the row locked for the transaction. */
    private SupportTicket lockTicketForCaller(Long id) {
        SupportTicket ticket = ticketRepository.lockById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        if (isTenantCaller() && !Objects.equals(ticket.getCompanyId(), securityUtil.getCurrentCompanyId())) {
            throw new ResourceNotFoundException("Ticket not found");
        }
        return ticket;
    }

    private void logAudit(Long companyId, Long userId, AuditAction action, Long resourceId,
                          String description, String changes) {
        AuditLog log = AuditLog.builder()
                .company(companyId != null ? companyRepository.getReferenceById(companyId) : null)
                .performedBy(userId != null ? userRepository.getReferenceById(userId) : null)
                .action(action)
                .entityId(resourceId)
                .entityType(AuditEntityType.SUPPORT_TICKET)
                .oldValue(description)
                .newValue(changes)
                .build();
        auditRepository.save(log);
    }
}
