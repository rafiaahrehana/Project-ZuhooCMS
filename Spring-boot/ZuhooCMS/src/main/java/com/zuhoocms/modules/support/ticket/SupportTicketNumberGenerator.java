package com.zuhoocms.modules.support.ticket;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.Year;

/**
 * Globally unique ticket numbers ({@code TKT-YYYY-NNNNNN}) from a Postgres sequence, replacing {@code count() + 1}, which collided on concurrent creates and re-issued numbers after a soft delete.
 * {@code ddl-auto=update} never creates sequences for non-id columns, so it is created here idempotently, on startup and lazily before the first draw.
 * It starts above the highest suffix already in {@code support_tickets} (soft-deleted rows included) and never resets, so numbers stay unique across years.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SupportTicketNumberGenerator implements ApplicationRunner {

    static final String SEQUENCE = "support_ticket_number_seq";

    private static final String MAX_EXISTING_SQL =
            "SELECT COALESCE(MAX(CAST(substring(ticket_number from '([0-9]+)$') AS BIGINT)), 0) FROM support_tickets";

    private final JdbcTemplate jdbcTemplate;

    private volatile boolean ready;

    @Override
    public void run(ApplicationArguments args) {
        try {
            ensureSequence();
        } catch (RuntimeException ex) {
            // Not fatal at startup - next() retries before drawing a number.
            log.warn("Could not initialise {}: {}", SEQUENCE, ex.getMessage());
        }
    }

    synchronized void ensureSequence() {
        if (ready) return;
        Long max = jdbcTemplate.queryForObject(MAX_EXISTING_SQL, Long.class);
        long maxExisting = max != null ? max : 0L;
        jdbcTemplate.execute("CREATE SEQUENCE IF NOT EXISTS " + SEQUENCE + " START WITH " + (maxExisting + 1));
        // An existing sequence (from an earlier run) must still be ahead of every stored number.
        Long next = jdbcTemplate.queryForObject(
                "SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM " + SEQUENCE, Long.class);
        if (next != null && next <= maxExisting) {
            jdbcTemplate.queryForObject("SELECT setval('" + SEQUENCE + "', ?)", Long.class, maxExisting);
            log.info("{} moved forward to {}", SEQUENCE, maxExisting);
        }
        ready = true;
    }

    public String next() {
        if (!ready) {
            ensureSequence();
        }
        Long n = jdbcTemplate.queryForObject("SELECT nextval('" + SEQUENCE + "')", Long.class);
        return String.format("TKT-%04d-%06d", Year.now().getValue(), n);
    }
}
