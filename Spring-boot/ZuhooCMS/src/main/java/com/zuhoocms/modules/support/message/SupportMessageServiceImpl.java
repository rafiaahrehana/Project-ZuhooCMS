package com.zuhoocms.modules.support.message;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.support.agent.SupportAgent;
import com.zuhoocms.modules.support.agent.SupportAgentRepository;
import com.zuhoocms.modules.support.agent.SupportAgentStatus;
import com.zuhoocms.modules.support.ticket.SupportTicket;
import com.zuhoocms.modules.support.ticket.SupportTicketRepository;
import com.zuhoocms.modules.support.ticket.TicketStatus;
import com.zuhoocms.modules.support.ticket.TicketType;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class SupportMessageServiceImpl implements SupportMessageService {

    private final SupportMessageRepository messageRepository;
    private final SupportTicketRepository ticketRepository;
    private final UserRepository userRepository;
    private final ClientRepository clientRepository;
    private final SupportAgentRepository supportAgentRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final NotificationService notificationService;
    private final SimpMessagingTemplate messagingTemplate;

    /** Platform roles allowed to moderate (delete) any message. */
    private static final Set<Role> SUPPORT_MANAGEMENT_ROLES =
            EnumSet.of(Role.SUPPORT_MANAGER, Role.SUPER_ADMIN, Role.SYSTEM_ADMIN);

    /** Staff post: the tenant branch re-checks companyId because findById is a PK lookup the Hibernate tenantFilter never applies to. */
    @Override
    @Transactional
    public SupportMessageResponse create(SupportMessageRequest request) {
        User sentBy = securityUtil.getCurrentUser();
        if (sentBy == null) {
            throw new ForbiddenException("Not authenticated");
        }
        boolean platformStaff = sentBy.isPlatformUser();

        SupportTicket ticket;
        if (platformStaff) {
            ticket = ticketRepository.lockById(request.getTicketId())
                    .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        } else {
            authorizationService.checkPermission(PermissionCode.SUPPORT_MESSAGE_VIEW);
            ticket = ticketRepository.lockById(request.getTicketId())
                    .filter(t -> Objects.equals(t.getCompanyId(), securityUtil.getCurrentCompanyId()))
                    .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        }

        requireOpenForMessages(ticket);
        // Internal notes are platform-staff-only: a tenant must not create a message it can't see or that skips notifications.
        if (request.isInternal() && !platformStaff) {
            throw new ForbiddenException("Only platform support staff can add internal notes");
        }
        return postStaffMessage(ticket, sentBy, request);
    }

    /** Same effects as create(), but only a CUSTOMER_SUPPORT ticket of the caller's own company is reachable. */
    @Override
    @Transactional
    public SupportMessageResponse replyToClientTicket(Long ticketId, ClientTicketReplyRequest request) {
        User sentBy = securityUtil.getCurrentUser();
        if (sentBy == null) {
            throw new ForbiddenException("Not authenticated");
        }
        authorizationService.checkPermission(PermissionCode.SUPPORT_MESSAGE_VIEW);
        SupportTicket ticket = ticketRepository.lockById(ticketId)
                .filter(this::isOwnClientTicket)
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        requireOpenForMessages(ticket);
        SupportMessageRequest message = SupportMessageRequest.builder()
                .ticketId(ticketId)
                .message(request.getMessage())
                .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
                .attachmentFileName(request.getAttachmentFileName())
                .build();
        return postStaffMessage(ticket, sentBy, message);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportMessageResponse> getClientTicketMessagesForCompany(Long ticketId) {
        authorizationService.checkPermission(PermissionCode.SUPPORT_MESSAGE_VIEW);
        ticketRepository.findByIdAndCompanyId(ticketId, securityUtil.getCurrentCompanyId())
                .filter(this::isOwnClientTicket)
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        return messageRepository.findByTicketIdAndIsInternalFalseOrderByCreatedAtAsc(ticketId)
                .stream()
                .map(SupportMessageMapper::toResponse)
                .collect(Collectors.toList());
    }

    private boolean isOwnClientTicket(SupportTicket ticket) {
        return ticket.getTicketType() == TicketType.CUSTOMER_SUPPORT
                && Objects.equals(ticket.getCompanyId(), securityUtil.getCurrentCompanyId());
    }

    /** Saves a staff-authored message on an already resolved and access-checked ticket. */
    private SupportMessageResponse postStaffMessage(SupportTicket ticket, User sentBy, SupportMessageRequest request) {
        SupportMessage message = SupportMessage.builder()
                .ticket(ticket)
                .sentBy(sentBy)
                .message(request.getMessage())
                .messageType(request.getMessageType())
                .isInternal(request.isInternal())
                .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
                .attachmentFileName(request.getAttachmentFileName())
                .isResolution(request.isResolution())
                .build();

        message = messageRepository.save(message);

        // First external reply from the handling side starts the SLA "responded" clock (manual action still exists).
        if (!message.isInternal() && ticket.getFirstResponseTime() == null && isHandlingSide(ticket, sentBy)) {
            ticket.recordFirstResponse();
            ticketRepository.save(ticket);
        }

        SupportMessageResponse response = SupportMessageMapper.toResponse(message);

        // Internal notes are staff-only by definition - never alert the other side.
        if (!message.isInternal()) {
            notifyOtherParty(ticket, sentBy, response);
        }

        return response;
    }

    /** Client posts on their own ticket: isInternal is never taken from the request, a client message is always external. */
    @Override
    @Transactional
    public SupportMessageResponse createForClient(SupportMessageRequest request) {
        Client client = resolveClientForCurrentUser();
        SupportTicket ticket = ticketRepository
                .findByIdAndClientIdAndCompanyId(request.getTicketId(), client.getId(), client.getCompany().getId())
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        requireOpenForMessages(ticket);

        SupportMessage message = SupportMessage.builder()
                .ticket(ticket)
                .sentBy(client.getUser())
                .message(request.getMessage())
                .messageType(request.getMessageType())
                .isInternal(false)
                .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
                .attachmentFileName(request.getAttachmentFileName())
                .build();

        message = messageRepository.save(message);
        SupportMessageResponse response = SupportMessageMapper.toResponse(message);
        notifyOtherParty(ticket, client.getUser(), response);
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportMessageResponse> getClientMessages(Long ticketId) {
        Client client = resolveClientForCurrentUser();
        ticketRepository.findByIdAndClientIdAndCompanyId(ticketId, client.getId(), client.getCompany().getId())
                .orElseThrow(() -> new ResourceNotFoundException("Ticket not found"));
        // A client only ever sees external messages - isInternal notes are staff-only.
        return messageRepository.findByTicketIdAndIsInternalFalseOrderByCreatedAtAsc(ticketId)
                .stream()
                .map(SupportMessageMapper::toResponse)
                .collect(Collectors.toList());
    }

    private Client resolveClientForCurrentUser() {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            throw new BadRequestException("Not authenticated");
        }
        return clientRepository.findByUserId(current.getId())
                .orElseThrow(() -> new BadRequestException("No client profile linked to this account"));
    }

    private static void requireOpenForMessages(SupportTicket ticket) {
        if (ticket.getStatus() == TicketStatus.CLOSED) {
            throw new BadRequestException("This ticket is closed - reopen it to continue the conversation");
        }
    }

    /** Whose reply counts as first response: platform staff on PLATFORM_SUPPORT, anyone but the client on CUSTOMER_SUPPORT. */
    private static boolean isHandlingSide(SupportTicket ticket, User sender) {
        if (ticket.getTicketType() == TicketType.CUSTOMER_SUPPORT) {
            return sender.getRole() != Role.CLIENT;
        }
        return sender.isPlatformUser();
    }

    /** Branches on ticket type, not sender tenant-ness: both types have tenant-side senders, so confusing them would leak a client's message to platform SupportAgents. */
    private void notifyOtherParty(SupportTicket ticket, User sender, SupportMessageResponse response) {
        try {
            if (ticket.getTicketType() == TicketType.CUSTOMER_SUPPORT) {
                notifyOnCustomerSupportTicket(ticket, sender, response);
            } else {
                notifyOnPlatformSupportTicket(ticket, sender, response);
            }
        } catch (Exception ex) {
            log.warn("Support message notification failed for ticket {}: {}", ticket.getId(), ex.getMessage());
        }
    }

    /**
     * Company -> platform: assigned agent, else agents accepting tickets, else SUPPORT_MANAGER; see ServiceRequestServiceImpl.notifyAssignableStaff.
     * Platform -> company: whoever opened the ticket.
     * Also live-pushes to each recipient's personal queue; see ServiceRequestServiceImpl.pushChatMessage.
     */
    private void notifyOnPlatformSupportTicket(SupportTicket ticket, User sender, SupportMessageResponse response) {
        String actionUrl = "/support/tickets/" + ticket.getId();
        List<Long> recipients = new ArrayList<>();

        if (sender.isTenantUser()) {
            if (ticket.getAssignedToAgent() != null && ticket.getAssignedToAgent().getUser() != null) {
                recipients.add(ticket.getAssignedToAgent().getUser().getId());
            } else {
                for (SupportAgent agent : supportAgentRepository
                        .findByStatusAndAcceptingTicketsTrue(SupportAgentStatus.ACTIVE)) {
                    if (agent.getUser() != null) {
                        recipients.add(agent.getUser().getId());
                    }
                }
                if (recipients.isEmpty()) {
                    userRepository.findByRoleIn(List.of(Role.SUPPORT_MANAGER), Pageable.unpaged())
                            .forEach(u -> recipients.add(u.getId()));
                }
            }
            String message = "New message on ticket " + ticket.getTicketNumber()
                    + (ticket.getCompany() != null ? " from " + ticket.getCompany().getCompanyName() : "") + ".";
            for (Long recipientId : recipients) {
                notificationService.send(CreateNotificationRequest.of(
                        NotificationType.GENERAL, "New Support Message", message,
                        actionUrl, recipientId, ticket.getCompanyId()));
                pushChatMessage(ticket.getId(), recipientId, response);
            }
        } else if (ticket.getCreatedBy() != null) {
            Long recipientId = ticket.getCreatedBy().getId();
            String message = "Support replied on ticket " + ticket.getTicketNumber() + ".";
            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.GENERAL, "New Support Message", message,
                    actionUrl, recipientId, ticket.getCompanyId()));
            pushChatMessage(ticket.getId(), recipientId, response);
        }
    }

    /** Client -> company: assigned Employee else company owner (no unassigned-pool broadcast for CUSTOMER_SUPPORT yet); company -> client: the ticket's client. */
    private void notifyOnCustomerSupportTicket(SupportTicket ticket, User sender, SupportMessageResponse response) {
        String actionUrl = "/client/tickets/" + ticket.getId();
        boolean fromClient = ticket.getClient() != null && ticket.getClient().getUser() != null
                && ticket.getClient().getUser().getId().equals(sender.getId());

        if (fromClient) {
            Long recipientId = ticket.getAssignedEmployee() != null && ticket.getAssignedEmployee().getUser() != null
                    ? ticket.getAssignedEmployee().getUser().getId()
                    : ticket.getCompany() != null && ticket.getCompany().getOwner() != null
                        ? ticket.getCompany().getOwner().getId()
                        : null;
            if (recipientId == null) return;
            String message = "New message on ticket " + ticket.getTicketNumber()
                    + (ticket.getClient() != null ? " from " + ticket.getClient().getClientCompanyName() : "") + ".";
            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.GENERAL, "New Support Message", message,
                    actionUrl, recipientId, ticket.getCompanyId()));
            pushChatMessage(ticket.getId(), recipientId, response);
        } else if (ticket.getClient() != null && ticket.getClient().getUser() != null) {
            Long recipientId = ticket.getClient().getUser().getId();
            String message = "Support replied on ticket " + ticket.getTicketNumber() + ".";
            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.GENERAL, "New Support Message", message,
                    actionUrl, recipientId, ticket.getCompanyId()));
            pushChatMessage(ticket.getId(), recipientId, response);
        }
    }

    private void pushChatMessage(Long ticketId, Long recipientUserId, SupportMessageResponse message) {
        try {
            messagingTemplate.convertAndSendToUser(
                    recipientUserId.toString(), "/queue/support-tickets/" + ticketId + "/messages", message);
        } catch (Exception ex) {
            log.debug("Live chat push failed for user {} on ticket {}: {}", recipientUserId, ticketId, ex.getMessage());
        }
    }

    private boolean isTenantCaller() {
        User current = securityUtil.getCurrentUser();
        return current != null && !current.isPlatformUser();
    }

    /** SupportMessage has no tenantFilter: scope via the ticket, and 404 internal notes for non-platform callers. */
    private SupportMessage findMessageForCaller(Long id) {
        SupportMessage message = messageRepository.findWithTicketById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Message not found"));
        if (isTenantCaller()) {
            Long ticketCompanyId = message.getTicket() != null ? message.getTicket().getCompanyId() : null;
            if (!Objects.equals(ticketCompanyId, securityUtil.getCurrentCompanyId()) || message.isInternal()) {
                throw new ResourceNotFoundException("Message not found");
            }
        }
        return message;
    }

    @Override
    @Transactional(readOnly = true)
    public SupportMessageResponse getById(Long id) {
        checkTenantPermission();
        return SupportMessageMapper.toResponse(findMessageForCaller(id));
    }

    /** Tenants get the external thread only; platform staff get everything. */
    @Override
    @Transactional(readOnly = true)
    public Page<SupportMessageResponse> getByTicket(Long ticketId, Pageable pageable) {
        checkTenantPermission();
        assertTicketVisible(ticketId);
        Page<SupportMessage> page = isTenantCaller()
                ? messageRepository.findByTicketIdAndIsInternalFalse(ticketId, pageable)
                : messageRepository.findByTicketId(ticketId, pageable);
        return page.map(SupportMessageMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportMessageResponse> getExternalMessages(Long ticketId) {
        checkTenantPermission();
        assertTicketVisible(ticketId);
        return messageRepository.findByTicketIdAndIsInternalFalseOrderByCreatedAtAsc(ticketId)
                .stream()
                .map(SupportMessageMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportMessageResponse> getInternalNotes(Long ticketId) {
        if (isTenantCaller()) {
            // Defence in depth: the endpoint is platform-role only, but an impersonation principal is a tenant.
            throw new ForbiddenException("Internal notes are only visible to platform support staff");
        }
        assertTicketVisible(ticketId);
        return messageRepository.findByTicketIdAndIsInternalTrueOrderByCreatedAtAsc(ticketId)
                .stream()
                .map(SupportMessageMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** Only the author can edit their message, and not once the ticket is closed. */
    @Override
    @Transactional
    public SupportMessageResponse update(Long id, SupportMessageRequest request) {
        SupportMessage message = findMessageForCaller(id);
        User current = securityUtil.getCurrentUser();
        if (current == null || message.getSentBy() == null || !message.getSentBy().getId().equals(current.getId())) {
            throw new ForbiddenException("Only the author can edit this message");
        }
        requireOpenForMessages(message.getTicket());

        message.setMessage(request.getMessage());
        message.setAttachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl(), message.getAttachmentUrl()));

        message = messageRepository.save(message);
        return SupportMessageMapper.toResponse(message);
    }

    /** Deletable by the author, a platform support manager/admin, or the owning company's COMPANY_OWNER. */
    @Override
    @Transactional
    public SupportMessageResponse delete(Long id) {
        SupportMessage message = findMessageForCaller(id);
        User current = securityUtil.getCurrentUser();
        boolean author = current != null && message.getSentBy() != null
                && message.getSentBy().getId().equals(current.getId());
        boolean platformManager = current != null && current.isPlatformUser()
                && SUPPORT_MANAGEMENT_ROLES.contains(current.getRole());
        // Company scope (and "not an internal note") was already enforced by findMessageForCaller.
        boolean tenantOwner = current != null && current.getRole() == Role.COMPANY_OWNER;
        if (!author && !platformManager && !tenantOwner) {
            throw new ForbiddenException("Only the author or a manager can delete this message");
        }
        message.softDelete();
        messageRepository.save(message);
        return SupportMessageMapper.toResponse(message);
    }

    /** 404s a ticket the caller can't reach (tenant: another company's ticket). */
    private void assertTicketVisible(Long ticketId) {
        boolean visible = isTenantCaller()
                ? ticketRepository.findByIdAndCompanyId(ticketId, securityUtil.getCurrentCompanyId()).isPresent()
                : ticketRepository.existsById(ticketId);
        if (!visible) {
            throw new ResourceNotFoundException("Ticket not found: " + ticketId);
        }
    }

    // Platform staff have no CustomRole and are covered by @PreAuthorize, so only gate the tenant caller here.
    private void checkTenantPermission() {
        if (isTenantCaller()) {
            authorizationService.checkPermission(PermissionCode.SUPPORT_MESSAGE_VIEW);
        }
    }
}
