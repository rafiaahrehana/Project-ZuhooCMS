package com.zuhoocms.modules.support.message;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.util.List;

public interface SupportMessageService {
    SupportMessageResponse create(SupportMessageRequest request);
    SupportMessageResponse getById(Long id);
    Page<SupportMessageResponse> getByTicket(Long ticketId, Pageable pageable);
    List<SupportMessageResponse> getExternalMessages(Long ticketId);
    List<SupportMessageResponse> getInternalNotes(Long ticketId);
    SupportMessageResponse update(Long id, SupportMessageRequest request);
    SupportMessageResponse delete(Long id);

    // Client-facing: isInternal is always forced false, so a client can never see or create an internal staff note.
    SupportMessageResponse createForClient(SupportMessageRequest request);
    List<SupportMessageResponse> getClientMessages(Long ticketId);

    // Company-side Client Chat, 404 for any other ticket; same paths/shapes as servicedesk-service.
    List<SupportMessageResponse> getClientTicketMessagesForCompany(Long ticketId);
    SupportMessageResponse replyToClientTicket(Long ticketId, ClientTicketReplyRequest request);
}
