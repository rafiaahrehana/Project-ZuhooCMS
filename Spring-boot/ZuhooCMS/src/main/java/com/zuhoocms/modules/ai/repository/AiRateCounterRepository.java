package com.zuhoocms.modules.ai.repository;

import com.zuhoocms.modules.ai.entity.AiRateCounter;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;

public interface AiRateCounterRepository extends JpaRepository<AiRateCounter, Long> {

    /** Creates the window's row at zero if it does not exist yet; a no-op when it does (or a racer just made it). */
    @Modifying
    @Query(value = """
        INSERT INTO ai_rate_counters (scope_key, window_start, request_count)
        VALUES (:scope, :windowStart, 0)
        ON CONFLICT (scope_key, window_start) DO NOTHING
        """, nativeQuery = true)
    int ensureRow(@Param("scope") String scope, @Param("windowStart") LocalDateTime windowStart);

    /** Reserves one request if the window is under {@code limit}: check and increment in one statement, so Postgres' row lock serialises concurrent reservations. */
    @Modifying
    @Query(value = """
        UPDATE ai_rate_counters
           SET request_count = request_count + 1
         WHERE scope_key = :scope AND window_start = :windowStart AND request_count < :limit
        """, nativeQuery = true)
    int tryIncrement(@Param("scope") String scope, @Param("windowStart") LocalDateTime windowStart,
                     @Param("limit") int limit);

    /** Gives back a slot reserved moments ago when a later check in the same reservation failed. */
    @Modifying
    @Query(value = """
        UPDATE ai_rate_counters
           SET request_count = GREATEST(request_count - 1, 0)
         WHERE scope_key = :scope AND window_start = :windowStart
        """, nativeQuery = true)
    int decrement(@Param("scope") String scope, @Param("windowStart") LocalDateTime windowStart);
}
