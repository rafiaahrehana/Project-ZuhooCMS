package com.zuhoocms.modules.support.agent;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface SupportAgentRepository extends JpaRepository<SupportAgent, Long> {

    @EntityGraph(attributePaths = {"user"})
    Optional<SupportAgent> findByUserId(Long userId);

    @EntityGraph(attributePaths = {"user"})
    Page<SupportAgent> findByStatus(SupportAgentStatus status, Pageable pageable);

    @EntityGraph(attributePaths = {"user"})
    List<SupportAgent> findByStatusAndAcceptingTicketsTrue(SupportAgentStatus status);

    @Override
    @EntityGraph(attributePaths = {"user"})
    Page<SupportAgent> findAll(Pageable pageable);

    /** Row lock so two concurrent assignments to one agent serialise and the count checked against maxConcurrentTickets is never stale. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT a FROM SupportAgent a WHERE a.id = :id")
    Optional<SupportAgent> lockById(@Param("id") Long id);
}
