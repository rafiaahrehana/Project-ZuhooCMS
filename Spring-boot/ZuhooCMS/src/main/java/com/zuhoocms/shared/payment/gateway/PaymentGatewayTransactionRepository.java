package com.zuhoocms.shared.payment.gateway;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PaymentGatewayTransactionRepository
        extends JpaRepository<PaymentGatewayTransaction, Long> {

    Optional<PaymentGatewayTransaction> findByTranId(String tranId);

    /** The success redirect and the IPN arrive near-concurrently for one tran_id: the row lock closes handleSuccess()'s check-then-act gap, preventing a double credit. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT t FROM PaymentGatewayTransaction t WHERE t.tranId = :tranId")
    Optional<PaymentGatewayTransaction> findByTranIdForUpdate(@Param("tranId") String tranId);

    /** Has this validation id already settled a different transaction? */
    boolean existsByValIdAndIdNot(String valId, Long id);

    /** Confirmed charges to retry; {@code applied = false} deliberately excludes NULL - see PaymentGatewayTransaction#applied. */
    @Query("""
        SELECT t.tranId FROM PaymentGatewayTransaction t
        WHERE t.status = com.zuhoocms.shared.payment.gateway.GatewayTransactionStatus.SUCCESS
          AND t.applied = false
          AND (t.applyAttempts IS NULL OR t.applyAttempts < :maxAttempts)
        ORDER BY t.id
        """)
    List<String> findUnappliedTranIds(@Param("maxAttempts") int maxAttempts, Pageable pageable);
}
