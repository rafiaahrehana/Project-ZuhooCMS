package com.zuhoocms.modules.support.ticket;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface SupportTicketService {

    SupportTicketResponse create(SupportTicketRequest request);
    SupportTicketResponse getById(Long id);
    SupportTicketResponse getByTicketNumber(String number);
    Page<SupportTicketResponse> getAll(Pageable pageable);
    Page<SupportTicketResponse> getByCompany(Long companyId, Pageable pageable);
    Page<SupportTicketResponse> getByStatus(TicketStatus status, Pageable pageable);
    Page<SupportTicketResponse> getAssignedToMe(Pageable pageable);
    Page<SupportTicketResponse> getMyTickets(Long userId, Pageable pageable);

    void assignToAgent(Long ticketId, Long agentId);
    void reassignToAgent(Long ticketId, Long newAgentId, String reason);
    void escalate(Long ticketId, String reason);

    void recordFirstResponse(Long ticketId);
    void resolve(Long ticketId, String resolutionNotes);
    void close(Long ticketId);
    void reopen(Long ticketId, String reason);

    void recordSatisfaction(Long ticketId, int rating, String feedback);

    List<SupportTicketResponse> getSLABreachedTickets();
    List<SupportTicketResponse> getOpenCriticalTickets();

    SupportTicketResponse update(Long id, SupportTicketPatchRequest request);
    void delete(Long id);

    // Client-facing CUSTOMER_SUPPORT against the client's own client-company, ownership-checked separately from the methods above - see SupportTicketServiceImpl.
    SupportTicketResponse createForClient(SupportTicketRequest request);
    Page<SupportTicketResponse> getMyClientTickets(Pageable pageable);
    SupportTicketResponse getClientTicketById(Long id);

    // Staff-facing counterpart: this company's own clients' tickets ("Client Chat"), separate from getAll()/getByStatus(), which are PLATFORM_SUPPORT only.
    Page<SupportTicketResponse> getClientTicketsForCompany(Pageable pageable);
    Page<SupportTicketResponse> getClientTicketsForCompanyByStatus(TicketStatus status, Pageable pageable);
    // Client Chat detail, 404 for any other ticket; same path/shape as servicedesk-service.
    SupportTicketResponse getClientTicketForCompany(Long id);
}
