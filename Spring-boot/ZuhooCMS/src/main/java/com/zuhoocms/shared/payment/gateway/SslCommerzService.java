package com.zuhoocms.shared.payment.gateway;

import java.math.BigDecimal;
import java.util.Map;

public interface SslCommerzService {

    /** Starts a checkout and returns the SSLCommerz GatewayPageURL to redirect the payer to. */
    String initiate(GatewayPurpose purpose, Long targetId, BigDecimal amount);

    /** Success callback / IPN: validates val_id server-side, then applies the payment; idempotent, a transaction is only ever applied once. */
    GatewayTransactionStatus handleSuccess(Map<String, String> params);

    /** Applies a confirmed charge left with applied = false, in its own transaction, storing any error on the row; used by handleSuccess() and GatewayApplyRetryScheduler, not exposed by a controller. */
    boolean applyConfirmedTransaction(String tranId);

    void markFailed(String tranId);

    void markCancelled(String tranId);
}
