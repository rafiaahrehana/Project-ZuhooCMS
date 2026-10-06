package com.zuhoocms.modules.support.sla;


import com.zuhoocms.modules.support.ticket.TicketPriority;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface SLAPolicyRepository extends JpaRepository<SLAPolicy, Long> {

    // Newest wins: legacy data can hold more than one policy per priority, and a single-result lookup then throws IncorrectResultSize and 500s ticket creation.
    Optional<SLAPolicy> findFirstByApplicablePriorityAndActiveTrueOrderByIdDesc(TicketPriority priority);

    Optional<SLAPolicy> findFirstByApplicablePriorityOrderByIdDesc(TicketPriority priority);

    List<SLAPolicy> findByActiveTrue();

    /** Duplicate check on create: any live (non-deleted) policy already covering this priority. */
    boolean existsByApplicablePriority(TicketPriority priority);

    /** Duplicate check on update: another ACTIVE policy for the same priority. */
    boolean existsByApplicablePriorityAndActiveTrueAndIdNot(TicketPriority priority, Long id);
}
