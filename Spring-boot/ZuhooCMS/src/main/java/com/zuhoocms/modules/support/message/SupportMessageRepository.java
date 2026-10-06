package com.zuhoocms.modules.support.message;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface SupportMessageRepository extends JpaRepository<SupportMessage, Long> {

    @EntityGraph(attributePaths = {"sentBy", "ticket"})
    Optional<SupportMessage> findWithTicketById(Long id);

    @EntityGraph(attributePaths = {"sentBy"})
    Page<SupportMessage> findByTicketId(Long ticketId, Pageable pageable);

    /** Tenant/client view of a ticket's thread - internal staff notes never included. */
    @EntityGraph(attributePaths = {"sentBy"})
    Page<SupportMessage> findByTicketIdAndIsInternalFalse(Long ticketId, Pageable pageable);

    List<SupportMessage> findByTicketIdOrderByCreatedAtAsc(Long ticketId);

    long countByTicketIdAndIsInternal(Long ticketId, boolean isInternal);

    @EntityGraph(attributePaths = {"sentBy"})
    List<SupportMessage> findByTicketIdAndIsInternalFalseOrderByCreatedAtAsc(Long ticketId);

    @EntityGraph(attributePaths = {"sentBy"})
    List<SupportMessage> findByTicketIdAndIsInternalTrueOrderByCreatedAtAsc(Long ticketId);
}
