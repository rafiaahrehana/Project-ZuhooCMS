package com.zuhoocms.modules.ai.repository;

import com.zuhoocms.modules.ai.entity.AiConversationThread;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;

public interface AiConversationThreadRepository extends JpaRepository<AiConversationThread, Long> {

    Page<AiConversationThread> findByCompanyIdAndUserIdOrderByUpdatedAtDesc(
            Long companyId, Long userId, Pageable pageable);

    // Scoped by companyId and userId, not just id: a thread belongs only to the employee who started it, beyond the entity-level tenant filter.
    java.util.Optional<AiConversationThread> findByIdAndCompanyIdAndUserId(
            Long id, Long companyId, Long userId);

    /** Atomically claims the pending write-action, clearing it only if unchanged; returns 1 for the winner, 0 for a racing second confirm, which must execute nothing. */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("""
        UPDATE AiConversationThread t
           SET t.pendingAction = NULL, t.updatedAt = :now
         WHERE t.id = :id AND t.pendingAction = :expected
        """)
    int claimPendingAction(@Param("id") Long id, @Param("expected") String expected,
                           @Param("now") LocalDateTime now);

    /** Replaces (or clears, with null) the pending action - targeted, never a full-entity merge. */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("UPDATE AiConversationThread t SET t.pendingAction = :pending, t.updatedAt = :now WHERE t.id = :id")
    int setPendingAction(@Param("id") Long id, @Param("pending") String pending,
                         @Param("now") LocalDateTime now);

    /** Bumps updatedAt (thread list ordering) and sets the title once, from the first message. */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("""
        UPDATE AiConversationThread t
           SET t.updatedAt = :now,
               t.title = COALESCE(t.title, :title)
         WHERE t.id = :id
        """)
    int touch(@Param("id") Long id, @Param("title") String title, @Param("now") LocalDateTime now);
}
