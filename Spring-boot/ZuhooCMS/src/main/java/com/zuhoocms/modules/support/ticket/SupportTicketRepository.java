package com.zuhoocms.modules.support.ticket;

import jakarta.persistence.LockModeType;
import jakarta.persistence.QueryHint;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.QueryHints;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface SupportTicketRepository extends JpaRepository<SupportTicket, Long> {

    // Legacy count()+1 numbers can be shared by older rows, so take the newest instead of a single-result lookup that 500s.
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Optional<SupportTicket> findFirstByTicketNumberOrderByIdDesc(String ticketNumber);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Optional<SupportTicket> findFirstByTicketNumberAndCompanyIdOrderByIdDesc(String ticketNumber, Long companyId);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Optional<SupportTicket> findByIdAndCompanyId(Long id, Long companyId);

    /** Row lock for state transitions/assignment so concurrent writers serialise. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT t FROM SupportTicket t WHERE t.id = :id")
    Optional<SupportTicket> lockById(@Param("id") Long id);

    @Override
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findAll(Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Page<SupportTicket> findByCompanyIdAndStatus(Long companyId, TicketStatus status, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Page<SupportTicket> findByCompanyId(Long companyId, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findByStatus(TicketStatus status, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Page<SupportTicket> findByAssignedToAgentId(Long agentId, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    Page<SupportTicket> findByCreatedById(Long userId, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findByCreatedByIdAndCompanyId(Long userId, Long companyId, Pageable pageable);

    // "SLA breached" = open and either already flagged or past a deadline the scheduler hasn't swept; matching only unflagged rows makes a ticket vanish once marked.
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    @Query("SELECT t FROM SupportTicket t WHERE t.status NOT IN :closedStatuses AND ("
            + "t.slaBreached = true OR t.firstResponseBreached = true OR t.resolutionDeadline < :now "
            + "OR (t.firstResponseTime IS NULL AND t.firstResponseDeadline < :now)) "
            + "ORDER BY t.resolutionDeadline ASC")
    List<SupportTicket> findSlaBreached(@Param("closedStatuses") List<TicketStatus> closedStatuses,
                                        @Param("now") LocalDateTime now, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    @Query("SELECT t FROM SupportTicket t WHERE t.companyId = :companyId AND t.status NOT IN :closedStatuses AND ("
            + "t.slaBreached = true OR t.firstResponseBreached = true OR t.resolutionDeadline < :now "
            + "OR (t.firstResponseTime IS NULL AND t.firstResponseDeadline < :now)) "
            + "ORDER BY t.resolutionDeadline ASC")
    List<SupportTicket> findSlaBreached(@Param("companyId") Long companyId,
                                        @Param("closedStatuses") List<TicketStatus> closedStatuses,
                                        @Param("now") LocalDateTime now, Pageable pageable);

    // SlaBreachScheduler locks and returns the rows to mark with SKIP LOCKED, so two overlapping runs never notify the same ticket twice.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @QueryHints(@QueryHint(name = "jakarta.persistence.lock.timeout", value = "-2"))
    @Query("SELECT t FROM SupportTicket t WHERE t.resolutionDeadline < :now AND t.slaBreached = false AND t.status NOT IN :closedStatuses")
    List<SupportTicket> lockNewlyResolutionBreached(@Param("now") LocalDateTime now,
                                                    @Param("closedStatuses") List<TicketStatus> closedStatuses);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @QueryHints(@QueryHint(name = "jakarta.persistence.lock.timeout", value = "-2"))
    @Query("SELECT t FROM SupportTicket t WHERE t.firstResponseTime IS NULL AND t.firstResponseDeadline < :now "
            + "AND t.firstResponseBreached = false AND t.status NOT IN :closedStatuses")
    List<SupportTicket> lockNewlyFirstResponseBreached(@Param("now") LocalDateTime now,
                                                       @Param("closedStatuses") List<TicketStatus> closedStatuses);

    // Critical = CRITICAL priority and not yet resolved/closed; NEW and REOPENED must be included, being the ones nobody has picked up.
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    @Query("SELECT t FROM SupportTicket t WHERE t.status NOT IN :closedStatuses "
            + "AND t.priority = com.zuhoocms.modules.support.ticket.TicketPriority.CRITICAL ORDER BY t.createdAt ASC")
    List<SupportTicket> findOpenCritical(@Param("closedStatuses") List<TicketStatus> closedStatuses, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user"})
    @Query("SELECT t FROM SupportTicket t WHERE t.companyId = :companyId AND t.status NOT IN :closedStatuses "
            + "AND t.priority = com.zuhoocms.modules.support.ticket.TicketPriority.CRITICAL ORDER BY t.createdAt ASC")
    List<SupportTicket> findOpenCritical(@Param("companyId") Long companyId,
                                         @Param("closedStatuses") List<TicketStatus> closedStatuses, Pageable pageable);

    long countByStatusAndCompanyId(TicketStatus status, Long companyId);

    long countByCompanyIdAndStatusAndCreatedAtBetween(
            Long companyId, TicketStatus status, LocalDateTime from, LocalDateTime to);

    long countByAssignedToAgentId(Long agentId);

    long countByAssignedToAgentIdAndStatusNotIn(Long agentId, List<TicketStatus> closedStatuses);

    Page<SupportTicket> findByCompanyIdAndTitleContainingIgnoreCase(Long companyId, String keyword, Pageable pageable);

    // Scoped to company AND client, since findByIdAndCompanyId alone would let one client read another's ticket in the same company.
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findByClientIdAndCompanyId(Long clientId, Long companyId, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedEmployee", "assignedEmployee.user"})
    Optional<SupportTicket> findByIdAndClientIdAndCompanyId(Long id, Long clientId, Long companyId);

    // Type-scoped variants: without them getAll()/getByStatus() mix CUSTOMER_SUPPORT tickets into the company's PLATFORM_SUPPORT inbox, and vice versa.
    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findByCompanyIdAndTicketType(Long companyId, TicketType ticketType, Pageable pageable);

    @EntityGraph(attributePaths = {"createdBy", "category", "assignedToAgent", "assignedToAgent.user", "assignedEmployee", "assignedEmployee.user"})
    Page<SupportTicket> findByCompanyIdAndTicketTypeAndStatus(Long companyId, TicketType ticketType, TicketStatus status, Pageable pageable);
}
