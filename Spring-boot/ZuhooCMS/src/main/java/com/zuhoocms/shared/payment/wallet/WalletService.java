package com.zuhoocms.shared.payment.wallet;

import com.zuhoocms.enums.WalletTransactionType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;

public interface WalletService {

    WalletResponse getOrCreateWallet();

    Page<WalletTransactionResponse> getTransactions(WalletTransactionType type, Pageable pageable);

    Wallet debit(String contextType, Long contextId, BigDecimal amount, String reference, String notes);

    Wallet credit(String contextType, Long contextId, BigDecimal amount, WalletTransactionType type,
                  String reference, String notes);

    /** Idempotent {@link #credit} by (wallet, type, reference), returning false if already booked; the check runs under the wallet row lock so concurrent callers cannot both credit. */
    boolean creditOnce(String contextType, Long contextId, BigDecimal amount, WalletTransactionType type,
                       String reference, String notes);
}
