package com.zuhoocms.modules.support.contextswitch;

import com.zuhoocms.auth.user.User;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface SupportContextSwitchRepository extends JpaRepository<SupportContextSwitch, Long> {

    /** A user's active switches, newest first; a list rather than an Optional, since legacy rows can leave more than one active and a single-result lookup then 500s. */
    @EntityGraph(attributePaths = {"supportAgent", "viewedCompany"})
    List<SupportContextSwitch> findBySupportAgentIdAndStillActiveTrueOrderBySwitchedInTimeDesc(Long agentId);

    @EntityGraph(attributePaths = {"supportAgent", "viewedCompany"})
    Page<SupportContextSwitch> findBySupportAgentId(Long agentId, Pageable pageable);

    @EntityGraph(attributePaths = {"supportAgent", "viewedCompany"})
    List<SupportContextSwitch> findByStillActiveTrueOrderBySwitchedInTimeDesc();

    @EntityGraph(attributePaths = {"supportAgent", "viewedCompany"})
    Optional<SupportContextSwitch> findWithDetailsById(Long id);

    /** Ids of switches still active past the cut-off - the expiry job ends each in its own transaction. */
    @Query("SELECT s.id FROM SupportContextSwitch s WHERE s.stillActive = true AND s.switchedInTime < :cutoff")
    List<Long> findActiveIdsSwitchedInBefore(@Param("cutoff") LocalDateTime cutoff);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM SupportContextSwitch s WHERE s.id = :id")
    Optional<SupportContextSwitch> lockById(@Param("id") Long id);

    /** Serialises switchContext() per user: without the row lock two concurrent switches both see "no active switch" and both insert one. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT u FROM User u WHERE u.id = :userId")
    Optional<User> lockUser(@Param("userId") Long userId);
}
