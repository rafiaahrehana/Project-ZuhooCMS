package com.zuhoocms.modules.finance.payment;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface PaymentReceiptService {
    PaymentReceiptResponse create(PaymentReceiptRequest request);
    PaymentReceiptResponse getById(Long id);
    Page<PaymentReceiptResponse> getAll(Pageable pageable);

    /** The caller's own payment receipts - resolves their Client record from the security context. */
    Page<PaymentReceiptResponse> getMyReceipts(Pageable pageable);
    void confirmPayment(Long id);
    void markAsDeposited(Long id, String bank);

    /** Unwinds a bounced CONFIRMED/DEPOSITED payment (NSF cheque, chargeback): posts Cr Cash / Dr AR, restores the invoice's paidAmount/status, and marks the receipt REVERSED. */
    void reverse(Long id, String reason);
    void delete(Long id);
}
