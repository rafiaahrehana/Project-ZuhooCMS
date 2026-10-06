package com.zuhoocms.modules.finance.generalledger;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Objects;
import java.util.function.Supplier;

/**
 * Hands out finance document numbers of the form {@code PREFIX-YYYY-NNNNNN} (e.g. {@code JE-2026-000001}) from a counter row.
 *
 * <p>Callers pass the prefix already carrying the year, so the rendered number keeps the shape existing documents, the Angular UI and search filters expect.
 * <p>A counter row replaces MAX(number)+1, under which two concurrent callers read the same maximum and produced the same number.
 *
 * <h2>Why this runs in the caller's transaction</h2>
 * <p>This used to be {@code REQUIRES_NEW}. That suspended the caller's transaction - which is already holding a pooled
 * connection - and borrowed a second one, so every document create needed <b>two</b> connections at once. At the default
 * HikariCP pool of 10, eleven or more concurrent creates deadlocked the pool against itself and failed with
 * {@code Connection is not available} after the 30s timeout; the connections in hand could not make progress, because the
 * connection each was waiting for was held by another create in the same state.
 * <p>Joining the caller's transaction ({@code REQUIRED}) removes the second connection entirely: one create, one connection,
 * so N concurrent creates need N connections and the pool merely queues them instead of deadlocking.
 *
 * <h2>Correctness under concurrency</h2>
 * <p>{@code UPDATE ... SET next_value = next_value + 1 ... RETURNING next_value - 1} is a single statement, so Postgres
 * takes the row lock, re-reads the committed row and increments it atomically; two callers can never read the same value.
 * The lock is now held until the caller commits rather than for microseconds, so concurrent creates of the <i>same</i>
 * (company, type, year) serialise over the rest of the posting. That is a throughput trade, not a correctness one, and it
 * is bounded by how long a create takes - unlike the old design, it cannot exhaust the pool.
 *
 * <h2>What a rollback does to a number</h2>
 * <p>The counter now moves in the <b>same</b> transaction as the document, so a rolled-back create rolls the counter back
 * with it: <b>no gap</b>, and the next document takes that number. No surviving document ever shares a number, because the
 * row lock means no other transaction could have read that value while the failing one held it. Under the old
 * {@code REQUIRES_NEW} the counter committed independently and a rolled-back create burned its number, leaving a gap.
 * <p>{@code seed} supplies the first value when no counter row exists yet, so numbers already issued under the old MAX+1
 * scheme (soft-deleted rows included) are not reissued.
 */
@Service
@RequiredArgsConstructor
public class DocumentNumberService {

    /** Document type key for manual journal entries (JE-YYYY-NNNNNN). */
    public static final String JOURNAL_ENTRY = "JOURNAL_ENTRY";

    /** Document type key for expenses (EXP-YYYY-NNNNNN). */
    public static final String EXPENSE = "EXPENSE";

    /** Document type key for vendor bills (BILL-YYYY-NNNNNN). */
    public static final String VENDOR_BILL = "VENDOR_BILL";

    /** Width of the running part of the number; existing numbers are six digits. */
    private static final int SEQUENCE_WIDTH = 6;

    private final FinanceDocumentSequenceRepository sequenceRepository;

    /**
     * Allocates the next document number for this company/type/year, on the caller's own connection and inside the caller's transaction.
     *
     * @param companyId owning tenant, or {@code null} for platform-level documents
     * @param year      taken from the document's own date, not from today
     * @param seed      first value for a counter that does not exist yet - one past the highest number already issued for that company/type/year
     */
    @Transactional(propagation = Propagation.REQUIRED)
    public String next(Long companyId, String docType, int year, String prefix, Supplier<Long> seed) {
        // Fast path: the counter exists, so one statement locks, increments and returns the value consumed.
        Long issued = sequenceRepository.bumpAndReturnIssued(companyId, docType, year);
        if (issued != null) {
            return prefix + pad(issued);
        }

        // Create path only. Serialise on this key: the UPDATE above can only lock a row that exists, and the first
        // document of a year has none yet, so without this two callers both see null and both insert.
        sequenceRepository.acquireSequenceLock(lockKey(companyId, docType, year));

        // Re-try under the lock: whoever held it before us may have created the row (and may have rolled back, in which
        // case there is still nothing here and we create it ourselves).
        issued = sequenceRepository.bumpAndReturnIssued(companyId, docType, year);
        if (issued != null) {
            return prefix + pad(issued);
        }

        long start = 1L;
        if (seed != null) {
            Long seeded = seed.get();
            if (seeded != null && seeded > start) {
                start = seeded;
            }
        }
        sequenceRepository.insertCounter(companyId, docType, year, start + 1L);
        return prefix + pad(start);
    }

    /** Six-digit zero padding, widening on its own once a company ever passes 999,999 documents. */
    private static String pad(long value) {
        String digits = Long.toString(value);
        if (digits.length() >= SEQUENCE_WIDTH) {
            return digits;
        }
        return "0".repeat(SEQUENCE_WIDTH - digits.length()) + digits;
    }

    /** Collapses the counter key into the single bigint {@code pg_advisory_xact_lock} takes; a collision only queues two unrelated document types behind each other, never a wrong number. */
    private static long lockKey(Long companyId, String docType, int year) {
        long h = 1125899906842597L; // large prime seed
        h = 31 * h + (companyId == null ? 0L : companyId);
        h = 31 * h + Objects.hashCode(docType);
        h = 31 * h + year;
        return h;
    }
}
