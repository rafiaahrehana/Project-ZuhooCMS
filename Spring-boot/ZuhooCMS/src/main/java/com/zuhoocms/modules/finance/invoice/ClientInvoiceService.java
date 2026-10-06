package com.zuhoocms.modules.finance.invoice;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.util.List;
import com.zuhoocms.enums.InvoiceStatus;

public interface ClientInvoiceService {

    ClientInvoiceResponse create(ClientInvoiceRequest request);

    /** System entry point for an invoice raised as a side effect of a client's own authorized action; skips the staff-only INVOICE_CREATE check create() enforces. */
    ClientInvoiceResponse createForServiceRequest(Long companyId, ClientInvoiceRequest request);

    /** System entry point with no security context (async listeners, schedulers), the create-side twin of sendInvoiceForCompany(); never exposed by a controller. */
    ClientInvoiceResponse createForCompany(Long companyId, ClientInvoiceRequest request);
    ClientInvoiceResponse getById(Long id);

    /** Staff (INVOICE_VIEW) may download any invoice in their company; a CLIENT may only download their own. */
    byte[] generatePdf(Long id);
    ClientInvoiceResponse getByInvoiceNumber(String number);
    Page<ClientInvoiceResponse> getAll(Pageable pageable);
    Page<ClientInvoiceResponse> getByStatus(InvoiceStatus status, Pageable pageable);
    Page<ClientInvoiceResponse> getByClient(Long clientId, Pageable pageable);

    /** The caller's own invoices - resolves their Client record from the security context. */
    Page<ClientInvoiceResponse> getMyInvoices(Pageable pageable);
    ClientInvoiceResponse update(Long id, ClientInvoiceRequest request);
    void sendInvoice(Long id);

    /** Same system-entry-point exemption as createForServiceRequest() - see its javadoc. */
    void sendInvoiceForServiceRequest(Long id);

    /** System entry point with no security context: issues the invoice by explicit company id instead of the caller's tenant. */
    void sendInvoiceForCompany(Long companyId, Long id);
    void recordPayment(Long id, java.math.BigDecimal amount);

    /** System entry point (e.g. payment gateway callbacks) - no security context. */
    void recordPaymentForCompany(Long companyId, Long id, java.math.BigDecimal amount);

    /** Posts the GL entry on the given date instead of today, for callers whose source document carries its own date. */
    void recordPaymentForCompany(Long companyId, Long id, java.math.BigDecimal amount, java.time.LocalDate paymentDate);
    void markAsOverdue(Long id);
    List<ClientInvoiceResponse> getOverdueInvoices();

    /** Reverses any GL posting the invoice already made, then marks it CANCELLED. */
    void cancelInvoice(Long id);

    /** DRAFT only - anything already sent/posted must go through cancelInvoice(). */
    void delete(Long id);

    /** Called when a client cancels their own service request (see ServiceRequestServiceImpl#cancel): a paid invoice files a Refund request for staff review, otherwise it is cancelled and reversed immediately. */
    void cancelOrRefundForServiceRequest(Long companyId, Long invoiceId);

    /** Used when an accepted quotation replaces an earlier invoice: as cancelOrRefundForServiceRequest(), but marks the superseded invoice VOIDED rather than CANCELLED. */
    void voidSupersededForServiceRequest(Long companyId, Long invoiceId);

    /** Staff-raised refund (INVOICE_REFUND) against a PAID/PARTIALLY_PAID invoice for up to the paid amount, filed as REQUESTED and completed by processRefund(). */
    RefundResponse requestRefund(Long invoiceId, RefundCreateRequest request);

    /** Pending (or any status) refund requests for staff review - permission INVOICE_VIEW. */
    Page<RefundResponse> listRefunds(com.zuhoocms.enums.RefundStatus status, Pageable pageable);

    /** Reverses the invoice's GL postings (cash actually leaves the company's books) and marks it REFUNDED. */
    void processRefund(Long refundId);

    /** Leaves the invoice untouched (still PAID) - no money moves. */
    void rejectRefund(Long refundId, String reason);

    /** Draft a concise invoice summary note with AI from the invoice's real client/amount/service data - not persisted */
    InvoiceSummaryDraftResponse draftSummaryWithAi(Long id);

    /** A partial write-down of what's owed without moving cash: posts Dr Sales Revenue / Cr Accounts Receivable, capped at the invoice's outstanding balance. */
    CreditNoteResponse issueCreditNote(CreditNoteRequest request);

    Page<CreditNoteResponse> listCreditNotes(Long invoiceId, Pageable pageable);
}
