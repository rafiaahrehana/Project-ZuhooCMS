package com.zuhoocms.modules.finance.payment;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.enums.InvoiceStatus;
import com.zuhoocms.modules.finance.generalledger.DocumentNumberService;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceService;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class PaymentReceiptServiceImpl implements PaymentReceiptService {

    private final PaymentReceiptRepository receiptRepository;
    private final ClientInvoiceRepository invoiceRepository;
    private final ClientRepository clientRepository;
    private final SecurityUtil securityUtil;
    private final ClientInvoiceService clientInvoiceService;
    private final GeneralLedgerService glService;
    private final DefaultAccountResolver accountResolver;
    private final AuthorizationService authorizationService;
    private final CompanyRepository companyRepository;
    private final NotificationService notificationService;
    private final DocumentNumberService documentNumberService;

    /** DocumentNumberService counter key for payment receipts. */
    static final String DOC_TYPE_RECEIPT = "PAYMENT_RECEIPT";

    /** Closed invoices: no payment may be confirmed against, or reversed back onto, them. */
    private static final java.util.Set<InvoiceStatus> CLOSED_INVOICE_STATUSES =
            java.util.EnumSet.of(InvoiceStatus.CANCELLED, InvoiceStatus.VOIDED, InvoiceStatus.REFUNDED);

    @Override
    @Transactional
    public PaymentReceiptResponse create(PaymentReceiptRequest request) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_CREATE);
        Long companyId = securityUtil.getCurrentCompanyId();

        Client client = clientRepository.findByIdAndCompanyId(request.getClientId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Client not found"));

        ClientInvoice invoice = null;
        if (request.getInvoiceId() != null) {
            invoice = invoiceRepository.findByIdAndCompanyId(request.getInvoiceId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Invoice not found"));
        }

        String receiptNumber = generateReceiptNumber(companyId, request.getPaymentDate());

        PaymentReceipt receipt = PaymentReceipt.builder()
                .companyId(companyId)
                .receiptNumber(receiptNumber)
                .invoice(invoice)
                .client(client)
                .amount(request.getAmount())
                .paymentDate(request.getPaymentDate())
                .paymentMethod(request.getPaymentMethod())
                .transactionReference(request.getTransactionReference())
                .status(PaymentStatus.PENDING)
                .notes(request.getNotes())
                .build();

        receipt = receiptRepository.save(receipt);
        return PaymentReceiptMapper.toResponse(receipt);
    }

    @Override
    @Transactional(readOnly = true)
    public PaymentReceiptResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_VIEW);
        return PaymentReceiptMapper.toResponse(findInTenant(id));
    }

    private PaymentReceipt findInTenant(Long id) {
        return receiptRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Payment receipt not found"));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PaymentReceiptResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return receiptRepository.findByCompanyId(companyId, pageable)
                .map(PaymentReceiptMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PaymentReceiptResponse> getMyReceipts(Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        Long userId = securityUtil.getCurrentUser().getId();
        Client client = clientRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("Client profile not found"));
        return receiptRepository.findByCompanyIdAndClientId(companyId, client.getId(), pageable)
                .map(PaymentReceiptMapper::toResponse);
    }

    @Override
    @Transactional
    public void confirmPayment(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_CONFIRM);
        PaymentReceipt receipt = findInTenant(id);
        if (receipt.getStatus() == PaymentStatus.CONFIRMED || receipt.getStatus() == PaymentStatus.DEPOSITED) {
            throw new BadRequestException("Payment receipt is already confirmed");
        }
        // Checked before confirming: a receipt against a CANCELLED invoice otherwise showed CONFIRMED while the invoice update and GL posting were skipped.
        if (receipt.getInvoice() != null) {
            ClientInvoice linkedInvoice = invoiceRepository
                    .findByIdAndCompanyId(receipt.getInvoice().getId(), receipt.getCompanyId()).orElse(null);
            if (linkedInvoice != null && CLOSED_INVOICE_STATUSES.contains(linkedInvoice.getStatus())) {
                throw new BadRequestException(
                        "Cannot confirm this payment: the linked invoice has been "
                                + linkedInvoice.getStatus().name().toLowerCase() + ".");
            }
        }
        receipt.confirmPayment();
        receiptRepository.save(receipt);

        // Confirming must also update the linked invoice and post to the GL, or a fully paid invoice sits at ISSUED and the cash never reaches Finance reports.
        if (receipt.getInvoice() != null) {
            ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(receipt.getInvoice().getId(), receipt.getCompanyId()).orElse(null);
            if (invoice != null && invoice.getStatus() != com.zuhoocms.enums.InvoiceStatus.CANCELLED) {
                clientInvoiceService.recordPaymentForCompany(receipt.getCompanyId(), receipt.getInvoice().getId(),
                        receipt.getAmount(), receipt.getPaymentDate() != null ? receipt.getPaymentDate() : LocalDate.now());
            }
        } else {
            String description = "Payment received (receipt " + receipt.getReceiptNumber() + ")";
            ChartOfAccount cash = accountResolver.cash(receipt.getCompanyId());
            ChartOfAccount ar = accountResolver.accountsReceivable(receipt.getCompanyId());
            glService.recordBalancedTransaction(receipt.getCompanyId(), List.of(
                            LedgerLine.debit(cash.getId(), receipt.getAmount()),
                            LedgerLine.credit(ar.getId(), receipt.getAmount())),
                    description, GlReferenceType.PAYMENT_RECEIPT, receipt.getId(), receipt.getReceiptNumber(),
                    receipt.getPaymentDate() != null ? receipt.getPaymentDate() : LocalDate.now());
        }

        notifyPaymentReceived(receipt);
    }

    private void notifyPaymentReceived(PaymentReceipt receipt) {
        Company company = companyRepository.findById(receipt.getCompanyId()).orElse(null);
        if (company == null || company.getOwner() == null) return;
        notificationService.send(com.zuhoocms.shared.notification.CreateNotificationRequest.of(
                com.zuhoocms.enums.NotificationType.PAYMENT_RECEIVED,
                "Payment received",
                "Payment of " + receipt.getAmount() + " (receipt " + receipt.getReceiptNumber() + ") has been confirmed.",
                "/finance/payments",
                company.getOwner().getId(),
                company.getId()));
    }

    @Override
    @Transactional
    public void reverse(Long id, String reason) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_CONFIRM);
        PaymentReceipt receipt = findInTenant(id);
        if (receipt.getStatus() != PaymentStatus.CONFIRMED && receipt.getStatus() != PaymentStatus.DEPOSITED) {
            throw new BadRequestException("Only a confirmed or deposited payment can be reversed");
        }

        Long companyId = receipt.getCompanyId();

        // Checked before anything posts: reversing onto a CANCELLED/VOIDED invoice reopened it, and onto a REFUNDED one took the same cash out of the books twice.
        ClientInvoice linkedInvoice = null;
        if (receipt.getInvoice() != null) {
            linkedInvoice = invoiceRepository.findByIdAndCompanyId(receipt.getInvoice().getId(), companyId).orElse(null);
            if (linkedInvoice != null && CLOSED_INVOICE_STATUSES.contains(linkedInvoice.getStatus())) {
                throw new BadRequestException("Cannot reverse this payment: the linked invoice is "
                        + linkedInvoice.getStatus().name().toLowerCase()
                        + ". A payment on a closed invoice has to be handled through a refund.");
            }
        }
        String description = "Payment reversal (receipt " + receipt.getReceiptNumber() + ")"
                + (reason != null && !reason.isBlank() ? " - " + reason : "");

        // Exact mirror of confirmPayment's posting, converting foreign-currency payments at the invoice's issue-time rate as the original did.
        BigDecimal amountBase = receipt.getAmount();
        if (receipt.getInvoice() != null && receipt.getInvoice().getExchangeRate() != null
                && receipt.getInvoice().getExchangeRate().compareTo(BigDecimal.ONE) != 0) {
            amountBase = receipt.getAmount().multiply(receipt.getInvoice().getExchangeRate())
                    .setScale(2, java.math.RoundingMode.HALF_UP);
        }
        ChartOfAccount cash = accountResolver.cash(companyId);
        ChartOfAccount ar = accountResolver.accountsReceivable(companyId);
        glService.recordBalancedTransaction(companyId, List.of(
                        LedgerLine.credit(cash.getId(), amountBase),
                        LedgerLine.debit(ar.getId(), amountBase)),
                description, GlReferenceType.PAYMENT_REVERSAL, receipt.getId(), receipt.getReceiptNumber(), LocalDate.now());

        // Restore the linked invoice: the client owes this money again.
        if (receipt.getInvoice() != null) {
            ClientInvoice invoice = linkedInvoice;
            if (invoice != null) {
                BigDecimal newPaid = invoice.getPaidAmount().subtract(receipt.getAmount()).max(BigDecimal.ZERO);
                invoice.setPaidAmount(newPaid);
                if (newPaid.compareTo(BigDecimal.ZERO) > 0) {
                    invoice.setStatus(com.zuhoocms.enums.InvoiceStatus.PARTIALLY_PAID);
                } else if (invoice.getDueDate() != null && invoice.getDueDate().isBefore(LocalDate.now())) {
                    invoice.setStatus(com.zuhoocms.enums.InvoiceStatus.OVERDUE);
                } else {
                    invoice.setStatus(com.zuhoocms.enums.InvoiceStatus.ISSUED);
                }
                invoice.setPaidDate(null);
                invoice.calculateTotals();
                invoiceRepository.save(invoice);
            }
        }

        receipt.setStatus(PaymentStatus.REVERSED);
        receipt.setReversedDate(LocalDate.now());
        receipt.setReversalReason(reason);
        receiptRepository.save(receipt);
    }

    @Override
    @Transactional
    public void markAsDeposited(Long id, String bank) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_CONFIRM);
        PaymentReceipt receipt = findInTenant(id);
        receipt.markAsDeposited(bank);
        receiptRepository.save(receipt);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYMENT_RECEIPT_DELETE);
        PaymentReceipt receipt = findInTenant(id);
        // A confirmed/deposited receipt has posted a GL entry and moved the invoice's paidAmount/status; only reverse() unwinds both, so only a PENDING receipt can be deleted.
        if (receipt.getStatus() == PaymentStatus.CONFIRMED || receipt.getStatus() == PaymentStatus.DEPOSITED) {
            throw new BadRequestException(
                    "Cannot delete a " + receipt.getStatus() + " payment receipt - reverse it instead");
        }
        receipt.softDelete();
        receiptRepository.save(receipt);
    }

    /** RCP-YYYY-NNNNNN from the locked DocumentNumberService counter, year from the receipt's own payment date; the unlocked MAX+1 raced and missed soft-deleted receipts still holding their number. */
    private String generateReceiptNumber(Long companyId, LocalDate paymentDate) {
        int year = (paymentDate != null ? paymentDate : LocalDate.now()).getYear();
        String prefix = "RCP-" + year + "-";
        return documentNumberService.next(companyId, DOC_TYPE_RECEIPT, year, prefix, () -> {
            Long max = receiptRepository.findMaxReceiptSequenceIncludingDeleted(companyId, prefix, prefix.length() + 1);
            return max == null ? 1L : max + 1L;
        });
    }
}
