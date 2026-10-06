package com.zuhoocms.modules.finance.invoice;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.InvoiceSummaryPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.modules.finance.generalledger.DocumentNumberService;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.enums.WalletTransactionType;
import com.zuhoocms.shared.payment.wallet.WalletRepository;
import com.zuhoocms.shared.payment.wallet.WalletService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import com.zuhoocms.enums.InvoiceStatus;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.enums.RefundStatus;

@Service
@RequiredArgsConstructor
@Slf4j
public class ClientInvoiceServiceImpl implements ClientInvoiceService {

    /** DocumentNumberService counter keys for the documents this service numbers. */
    static final String DOC_TYPE_INVOICE = "CLIENT_INVOICE";
    static final String DOC_TYPE_CREDIT_NOTE = "CREDIT_NOTE";

    /** Invoices that are closed: nothing may be sent, paid, reversed or cancelled on them. */
    private static final java.util.Set<InvoiceStatus> CLOSED_STATUSES =
            java.util.EnumSet.of(InvoiceStatus.CANCELLED, InvoiceStatus.VOIDED, InvoiceStatus.REFUNDED);

    private final ClientInvoiceRepository invoiceRepository;
    private final ClientRepository clientRepository;
    private final SecurityUtil securityUtil;
    private final GeneralLedgerService glService;
    private final DefaultAccountResolver accountResolver;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final AuthorizationService authorizationService;
    private final ServiceRequestRepository serviceRequestRepository;
    private final RefundRepository refundRepository;
    private final CreditNoteRepository creditNoteRepository;
    private final NotificationService notificationService;
    private final InvoicePdfService invoicePdfService;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final DocumentNumberService documentNumberService;
    private final WalletService walletService;
    private final WalletRepository walletRepository;

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new com.zuhoocms.shared.exception.BadRequestException("No company context");
        return id;
    }

    private ClientInvoice findInTenant(Long id) {
        return invoiceRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new com.zuhoocms.shared.exception.ResourceNotFoundException("Invoice not found: " + id));
    }

    @Override
    @Transactional
    public ClientInvoiceResponse create(ClientInvoiceRequest request) {
        authorizationService.checkPermission(PermissionCode.INVOICE_CREATE);
        return createInternal(securityUtil.getCurrentCompanyId(), request);
    }

    @Override
    @Transactional
    public ClientInvoiceResponse createForServiceRequest(Long companyId, ClientInvoiceRequest request) {
        return createInternal(companyId, request);
    }

    @Override
    @Transactional
    public ClientInvoiceResponse createForCompany(Long companyId, ClientInvoiceRequest request) {
        if (companyId == null) {
            throw new BadRequestException("No company context");
        }
        return createInternal(companyId, request);
    }

    // Shared by create() (INVOICE_CREATE-gated) and createForServiceRequest(), which is a side effect of a client action and must not require staff's INVOICE_CREATE.
    private ClientInvoiceResponse createInternal(Long companyId, ClientInvoiceRequest request) {
        if (companyId == null) {
            throw new BadRequestException("No company context");
        }
        if (request.getClientId() == null) {
            throw new BadRequestException("Client ID is required");
        }
        // Tenant-scoped: a plain findById let one company invoice another company's client.
        Client client = clientRepository.findByIdAndCompanyId(request.getClientId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Client not found"));

        // Same scoping as the client above: getReferenceById wrote the FK without checking, so a bogus, soft-deleted
        // or another tenant's id only surfaced as a 500 when the mapper read getServiceRequest().getTitle().
        // Resolved before the invoice number is drawn, so a 404 doesn't burn a counter value.
        com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest serviceRequest =
                request.getServiceRequestId() == null ? null
                        : serviceRequestRepository.findByIdAndCompanyId(request.getServiceRequestId(), companyId)
                                .orElseThrow(() -> new ResourceNotFoundException(
                                        "Service request not found: " + request.getServiceRequestId()));

        String currency = request.getCurrency() != null && !request.getCurrency().isBlank()
                ? request.getCurrency().trim().toUpperCase() : "BDT";
        BigDecimal exchangeRate = resolveExchangeRate(client, currency, request.getExchangeRate());

        LocalDate invoiceDate = request.getInvoiceDate() != null ? request.getInvoiceDate() : LocalDate.now();
        LocalDate dueDate = resolveDueDate(invoiceDate, request.getPaymentTerms(), request.getDueDate());

        String invoiceNumber = generateInvoiceNumber(companyId, invoiceDate);

        ClientInvoice invoice = ClientInvoice.builder()
                .companyId(companyId)
                .invoiceNumber(invoiceNumber)
                .client(client)
                .serviceRequest(serviceRequest)
                .invoiceDate(invoiceDate)
                .dueDate(dueDate)
                .taxAmount(request.getTaxAmount() != null ? request.getTaxAmount() : BigDecimal.ZERO)
                .taxRatePercent(request.getTaxRatePercent())
                .discountAmount(request.getDiscountAmount() != null ? request.getDiscountAmount() : BigDecimal.ZERO)
                .currency(currency)
                .exchangeRate(exchangeRate)
                .paymentTerms(request.getPaymentTerms())
                .description(request.getDescription())
                .notes(request.getNotes())
                .status(InvoiceStatus.DRAFT)
                .build();

        if (request.getItems() != null && !request.getItems().isEmpty()) {
            List<ClientInvoiceItem> items = request.getItems().stream()
                    .map(itemRequest -> {
                        ClientInvoiceItem item = ClientInvoiceItem.builder()
                                .invoice(invoice)
                                .description(itemRequest.getDescription())
                                .quantity(itemRequest.getQuantity())
                                .unitPrice(itemRequest.getUnitPrice())
                                .notes(itemRequest.getNotes())
                                .build();
                        item.calculateLineTotal();
                        return item;
                    })
                    .collect(Collectors.toList());
            invoice.setItems(items);
        }

        invoice.calculateTotals();
        ClientInvoice savedInvoice = invoiceRepository.save(invoice);

        return ClientInvoiceMapper.toResponse(savedInvoice);
    }

    /** Explicit due date wins; otherwise non-CUSTOM terms derive it from the invoice date (DUE_ON_RECEIPT = same day, NET_n = +n days). */
    static LocalDate resolveDueDate(LocalDate invoiceDate, PaymentTerms terms, LocalDate explicitDueDate) {
        if (explicitDueDate != null) {
            return explicitDueDate;
        }
        if (terms == null || terms == PaymentTerms.CUSTOM) {
            throw new BadRequestException("Due date is required unless payment terms other than CUSTOM are chosen");
        }
        LocalDate base = invoiceDate != null ? invoiceDate : LocalDate.now();
        return switch (terms) {
            case DUE_ON_RECEIPT -> base;
            case NET_15 -> base.plusDays(15);
            case NET_30 -> base.plusDays(30);
            case NET_45 -> base.plusDays(45);
            case NET_60 -> base.plusDays(60);
            case NET_90 -> base.plusDays(90);
            case CUSTOM -> throw new BadRequestException("Due date is required for CUSTOM payment terms");
        };
    }

    @Override
    @Transactional(readOnly = true)
    public ClientInvoiceResponse getById(Long id) {
        // Same shape as generatePdf(): staff need INVOICE_VIEW for any tenant invoice, a client is narrowed to their own.
        ClientInvoice invoice = findInTenant(id);
        if (!authorizationService.hasPermission(PermissionCode.INVOICE_VIEW)) {
            requireOwnInvoice(invoice);
        }
        return ClientInvoiceMapper.toResponse(invoice);
    }

    // No @Transactional on purpose: reads run inside aiTx.load(), which commits before the provider call so no connection is held across it - see AiTransactionBoundary.
    @Override
    public InvoiceSummaryDraftResponse draftSummaryWithAi(Long id) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);

        String prompt = aiTx.load(() -> {
            ClientInvoice invoice = findInTenant(id);

            String clientName = invoice.getClient() != null && invoice.getClient().getClientCompanyName() != null
                ? invoice.getClient().getClientCompanyName()
                : (invoice.getClient() != null && invoice.getClient().getUser() != null
                    ? invoice.getClient().getUser().getFullName() : "Client");
            String serviceName = invoice.getServiceRequest() != null ? invoice.getServiceRequest().getTitle()
                : invoice.getItems() != null && !invoice.getItems().isEmpty() ? invoice.getItems().get(0).getDescription()
                : "Services rendered";

            return InvoiceSummaryPromptBuilder.builder()
                .setClientName(clientName)
                .setServiceName(serviceName)
                .setAmount(invoice.getTotalAmount())
                .setPeriod(invoice.getInvoiceDate() + " to " + invoice.getDueDate())
                .build();
        });

        InvoiceSummaryDraftResponse response = new InvoiceSummaryDraftResponse();
        response.setSummary(aiService.generateRaw(AiFeature.INVOICE_SUMMARY, prompt));
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public byte[] generatePdf(Long id) {
        ClientInvoice invoice = findInTenant(id);
        if (!authorizationService.hasPermission(PermissionCode.INVOICE_VIEW)) {
            requireOwnInvoice(invoice);
        }
        Company company = invoice.getClient() != null ? invoice.getClient().getCompany() : null;
        EmailBranding.Data branding = emailBranding.from(company);
        return invoicePdfService.generate(invoice, company, branding);
    }

    private void requireOwnInvoice(ClientInvoice invoice) {
        var currentUser = securityUtil.getCurrentUser();
        Client myClient = currentUser != null
                ? clientRepository.findByUserId(currentUser.getId()).orElse(null)
                : null;
        if (myClient == null || invoice.getClient() == null
                || !invoice.getClient().getId().equals(myClient.getId())) {
            throw new ForbiddenException("Access denied: you can only download your own invoices");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public ClientInvoiceResponse getByInvoiceNumber(String number) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        ClientInvoice invoice = invoiceRepository.findByCompanyIdAndInvoiceNumber(requireCompanyId(), number)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found"));
        return ClientInvoiceMapper.toResponse(invoice);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientInvoiceResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return invoiceRepository.findByCompanyId(companyId, pageable)
                .map(ClientInvoiceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientInvoiceResponse> getByStatus(InvoiceStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return invoiceRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                .map(ClientInvoiceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientInvoiceResponse> getByClient(Long clientId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        return findByClientUnchecked(clientId, pageable);
    }

    private Page<ClientInvoiceResponse> findByClientUnchecked(Long clientId, Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        return invoiceRepository.findByCompanyIdAndClientId(companyId, clientId, pageable)
                .map(ClientInvoiceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientInvoiceResponse> getMyInvoices(Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        Long userId = securityUtil.getCurrentUser().getId();
        Client client = clientRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("Client profile not found"));
        Page<ClientInvoiceResponse> page = findByClientUnchecked(client.getId(), pageable);

        // Surface the latest refund's status so the client sees "Refund Requested"/"Refund Rejected" without a separate call.
        List<Long> invoiceIds = page.getContent().stream()
                .map(ClientInvoiceResponse::getId)
                .collect(Collectors.toList());
        if (!invoiceIds.isEmpty()) {
            Map<Long, RefundStatus> latestByInvoice = new HashMap<>();
            for (Refund r : refundRepository.findByClientInvoiceIdInAndCompanyIdOrderByCreatedAtDesc(invoiceIds, companyId)) {
                latestByInvoice.putIfAbsent(r.getClientInvoice().getId(), r.getStatus());
            }
            page.getContent().forEach(inv -> inv.setRefundStatus(latestByInvoice.get(inv.getId())));
        }

        return page;
    }

    @Override
    @Transactional
    public ClientInvoiceResponse update(Long id, ClientInvoiceRequest request) {
        authorizationService.checkPermission(PermissionCode.INVOICE_UPDATE);
        ClientInvoice invoice = findInTenant(id);  // tenant-scoped

        if (invoice.getStatus() != InvoiceStatus.DRAFT) {
            throw new com.zuhoocms.shared.exception.BadRequestException("Only DRAFT invoices can be updated");
        }

        LocalDate invoiceDate = request.getInvoiceDate() != null ? request.getInvoiceDate() : invoice.getInvoiceDate();
        invoice.setInvoiceDate(invoiceDate);
        invoice.setDueDate(resolveDueDate(invoiceDate, request.getPaymentTerms(), request.getDueDate()));
        invoice.setTaxAmount(request.getTaxAmount());
        invoice.setTaxRatePercent(request.getTaxRatePercent());
        invoice.setDiscountAmount(request.getDiscountAmount() != null ? request.getDiscountAmount() : BigDecimal.ZERO);
        if (request.getCurrency() != null && !request.getCurrency().isBlank()) {
            String currency = request.getCurrency().trim().toUpperCase();
            invoice.setCurrency(currency);
            invoice.setExchangeRate(resolveExchangeRate(invoice.getClient(), currency, request.getExchangeRate()));
        }
        invoice.setPaymentTerms(request.getPaymentTerms());
        invoice.setDescription(request.getDescription());
        invoice.setNotes(request.getNotes());

        if (request.getItems() != null) {
            invoice.getItems().clear();
            final ClientInvoice invoiceRef = invoice;
            List<ClientInvoiceItem> items = request.getItems().stream()
                    .map(itemRequest -> {
                        ClientInvoiceItem item = ClientInvoiceItem.builder()
                                .invoice(invoiceRef)
                                .description(itemRequest.getDescription())
                                .quantity(itemRequest.getQuantity())
                                .unitPrice(itemRequest.getUnitPrice())
                                .notes(itemRequest.getNotes())
                                .build();
                        item.calculateLineTotal();
                        return item;
                    })
                    .collect(Collectors.toList());
            invoice.getItems().addAll(items);
        }

        invoice.calculateTotals();
        invoice = invoiceRepository.save(invoice);

        return ClientInvoiceMapper.toResponse(invoice);
    }

    @Override
    @Transactional
    public void sendInvoice(Long id) {
        authorizationService.checkPermission(PermissionCode.INVOICE_SEND);
        sendInvoiceInternal(id);
    }

    @Override
    @Transactional
    public void sendInvoiceForServiceRequest(Long id) {
        sendInvoiceInternal(id);
    }

    @Override
    @Transactional
    public void sendInvoiceForCompany(Long companyId, Long id) {
        ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(id, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + id));
        issueInvoice(invoice);
    }

    private void sendInvoiceInternal(Long id) {
        issueInvoice(findInTenant(id));  // tenant-scoped
    }

    private void issueInvoice(ClientInvoice invoice) {
        if (invoice.getStatus() == InvoiceStatus.PAID || CLOSED_STATUSES.contains(invoice.getStatus())) {
            throw new BadRequestException("Cannot send a " + invoice.getStatus() + " invoice");
        }

        // Read before the status changes below - isRevenuePosted() looks at the status.
        boolean alreadyPosted = isRevenuePosted(invoice);

        // Only a DRAFT moves to ISSUED; re-sending just re-emails, since resetting to ISSUED hid a part payment or overdue state.
        if (invoice.getStatus() == InvoiceStatus.DRAFT) {
            invoice.setStatus(InvoiceStatus.ISSUED);
        }
        invoice.setSentDate(LocalDate.now());

        // Revenue is booked exactly once: posting Dr AR / Cr Revenue on every send doubled revenue and receivable.
        if (!alreadyPosted) {
            postInvoiceToLedger(invoice);
            invoice.setRevenuePosted(Boolean.TRUE);
        }
        invoiceRepository.save(invoice);

        try {
            Client client = invoice.getClient();
            if (client != null && client.getUser() != null && client.getCompany() != null) {
                EmailBranding.Data branding = emailBranding.from(client.getCompany());
                emailService.sendInvoiceEmail(client.getUser().getEmail(), client.getUser().getFirstName(), branding);
            }
        } catch (Exception ex) {
            // Email failure must not roll back the status change and GL posting - the invoice is already legally issued.
        }
    }

    /** Whether the issue-time revenue posting exists: the flag is authoritative, and pre-flag invoices left DRAFT only via issueInvoice(), which always posted. */
    private boolean isRevenuePosted(ClientInvoice invoice) {
        return Boolean.TRUE.equals(invoice.getRevenuePosted()) || invoice.getStatus() != InvoiceStatus.DRAFT;
    }

    /** subtotal - discount, floored at zero: totalAmount = this + taxAmount, so using it instead of raw subtotal keeps GL postings balanced. */
    private BigDecimal recognizedRevenue(ClientInvoice invoice) {
        BigDecimal discount = invoice.getDiscountAmount() != null ? invoice.getDiscountAmount() : BigDecimal.ZERO;
        return invoice.getSubtotal().subtract(discount).max(BigDecimal.ZERO);
    }

    /** Rate = 1 for base-currency invoices; required from the request otherwise. */
    private BigDecimal resolveExchangeRate(Client client, String currency, BigDecimal requestedRate) {
        String base = client != null && client.getCompany() != null && client.getCompany().getBaseCurrency() != null
                ? client.getCompany().getBaseCurrency() : "BDT";
        if (currency.equalsIgnoreCase(base)) {
            return BigDecimal.ONE;
        }
        if (requestedRate == null || requestedRate.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Exchange rate to " + base + " is required for a " + currency + " invoice");
        }
        return requestedRate;
    }

    /** Converts to base currency for GL posting: the ledger is single-currency and payments convert at the invoice's issue-time rate (no FX gain/loss). */
    private BigDecimal toBase(ClientInvoice invoice, BigDecimal amount) {
        if (amount == null) return BigDecimal.ZERO;
        BigDecimal rate = invoice.getExchangeRate() != null ? invoice.getExchangeRate() : BigDecimal.ONE;
        if (rate.compareTo(BigDecimal.ONE) == 0) return amount;
        return amount.multiply(rate).setScale(2, java.math.RoundingMode.HALF_UP);
    }

    /** Revenue recognition: Dr AR (full total) / Cr Sales Revenue (subtotal - discount) + Cr Tax Payable, balanced since revenue + tax = totalAmount. */
    private void postInvoiceToLedger(ClientInvoice invoice) {
        Long companyId = invoice.getCompanyId();
        String clientName = invoice.getClient() != null ? invoice.getClient().getClientCompanyName() : "client";
        String description = "Invoice " + invoice.getInvoiceNumber() + " issued to " + clientName;
        // Revenue is recognized as of the invoice's own date, not the Send click, or a backdated invoice lands in the wrong period.
        LocalDate transactionDate = invoice.getInvoiceDate() != null ? invoice.getInvoiceDate() : LocalDate.now();

        ChartOfAccount ar = accountResolver.accountsReceivable(companyId);
        ChartOfAccount revenue = accountResolver.salesRevenue(companyId);

        // Convert each credit leg, then make the AR debit their exact sum: rounding totalAmount independently could drift a cent and trip the balanced-batch check.
        BigDecimal revenueBase = toBase(invoice, recognizedRevenue(invoice));
        BigDecimal taxBase = invoice.getTaxAmount() != null && invoice.getTaxAmount().compareTo(BigDecimal.ZERO) > 0
                ? toBase(invoice, invoice.getTaxAmount()) : BigDecimal.ZERO;

        List<LedgerLine> lines = new java.util.ArrayList<>();
        lines.add(LedgerLine.debit(ar.getId(), revenueBase.add(taxBase)));
        lines.add(LedgerLine.credit(revenue.getId(), revenueBase));
        if (taxBase.compareTo(BigDecimal.ZERO) > 0) {
            ChartOfAccount tax = accountResolver.taxPayable(companyId);
            lines.add(LedgerLine.credit(tax.getId(), taxBase));
        }

        glService.recordBalancedTransaction(companyId, lines, description,
                GlReferenceType.INVOICE, invoice.getId(), invoice.getInvoiceNumber(), transactionDate);
    }

    @Override
    @Transactional
    public void recordPayment(Long id, BigDecimal amount) {
        authorizationService.checkPermission(PermissionCode.INVOICE_PAYMENT);
        recordPaymentForCompany(requireCompanyId(), id, amount);
    }

    @Override
    @Transactional
    public void recordPaymentForCompany(Long companyId, Long id, BigDecimal amount) {
        recordPaymentForCompany(companyId, id, amount, LocalDate.now());
    }

    @Override
    @Transactional
    public void recordPaymentForCompany(Long companyId, Long id, BigDecimal amount, LocalDate paymentDate) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new com.zuhoocms.shared.exception.BadRequestException("Payment amount must be positive");
        }

        ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(id, companyId)
            .orElseThrow(() -> new com.zuhoocms.shared.exception.ResourceNotFoundException("Invoice not found: " + id));

        if (CLOSED_STATUSES.contains(invoice.getStatus())) {
            throw new com.zuhoocms.shared.exception.BadRequestException(
                    "Cannot record payment for a " + invoice.getStatus().name().toLowerCase() + " invoice");
        }

        BigDecimal credited = invoice.getCreditedAmount() != null ? invoice.getCreditedAmount() : BigDecimal.ZERO;
        BigDecimal outstanding = invoice.getTotalAmount().subtract(invoice.getPaidAmount()).subtract(credited);
        if (amount.compareTo(outstanding) > 0) {
            throw new com.zuhoocms.shared.exception.BadRequestException("Payment amount exceeds outstanding balance");
        }

        BigDecimal newPaidAmount = invoice.getPaidAmount().add(amount);
        invoice.setPaidAmount(newPaidAmount);

        if (newPaidAmount.add(credited).compareTo(invoice.getTotalAmount()) >= 0) {
            invoice.setStatus(InvoiceStatus.PAID);
            invoice.setPaidDate(paymentDate);
        } else {
            invoice.setStatus(InvoiceStatus.PARTIALLY_PAID);
        }

        invoice.calculateTotals();
        invoiceRepository.save(invoice);

        // Cash received against a receivable: Dr Cash / Cr AR, converted at the invoice's issue-time rate.
        // Posted on the source document's own paymentDate, not today, or the period-lock check protects the wrong date.
        String description = "Payment received for invoice " + invoice.getInvoiceNumber();
        BigDecimal amountBase = toBase(invoice, amount);
        ChartOfAccount cash = accountResolver.cash(companyId);
        ChartOfAccount ar = accountResolver.accountsReceivable(companyId);
        glService.recordBalancedTransaction(companyId, List.of(
                        LedgerLine.debit(cash.getId(), amountBase),
                        LedgerLine.credit(ar.getId(), amountBase)),
                description, GlReferenceType.INVOICE, invoice.getId(), invoice.getInvoiceNumber(), paymentDate);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ClientInvoiceResponse> getOverdueInvoices() {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        Long companyId = requireCompanyId();
        List<InvoiceStatus> paidStatuses = List.of(InvoiceStatus.PAID, InvoiceStatus.CANCELLED,
                InvoiceStatus.VOIDED, InvoiceStatus.REFUNDED);
        return invoiceRepository.findOverdueInvoices(companyId, paidStatuses)
                .stream()
                .map(ClientInvoiceMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void cancelInvoice(Long id) {
        authorizationService.checkPermission(PermissionCode.INVOICE_CANCEL);
        ClientInvoice invoice = findInTenant(id);

        if (invoice.getStatus() == InvoiceStatus.CANCELLED) {
            throw new com.zuhoocms.shared.exception.BadRequestException("Invoice is already cancelled");
        }
        if (invoice.getStatus() == InvoiceStatus.VOIDED || invoice.getStatus() == InvoiceStatus.REFUNDED) {
            throw new com.zuhoocms.shared.exception.BadRequestException(
                    "Cannot cancel a " + invoice.getStatus().name().toLowerCase() + " invoice");
        }
        if (invoice.getStatus() == InvoiceStatus.PAID) {
            throw new com.zuhoocms.shared.exception.BadRequestException(
                    "Cannot cancel a fully paid invoice - issue a refund/credit note instead");
        }
        // Cancelling a part-paid invoice would credit Cash for the paid amount as if it had been handed back, so the payment must be dealt with first.
        if (hasPayments(invoice)) {
            throw new com.zuhoocms.shared.exception.BadRequestException(
                    "Cannot cancel an invoice that has received payments (" + invoice.getPaidAmount()
                            + " paid) - refund the payment first, or issue a credit note for the unpaid balance");
        }

        // Invoices never posted to the ledger (DRAFT) have nothing to reverse.
        boolean wasPosted = isRevenuePosted(invoice);

        invoice.setStatus(InvoiceStatus.CANCELLED);
        invoiceRepository.save(invoice);

        if (wasPosted) {
            reverseInvoiceLedger(invoice);
        }
    }

    private static boolean hasPayments(ClientInvoice invoice) {
        return invoice.getPaidAmount() != null && invoice.getPaidAmount().compareTo(BigDecimal.ZERO) > 0;
    }

    /** Cancellation reversal: Cr AR / Dr Sales Revenue + Dr Tax Payable, net of credit notes. No cash leg - see cancelInvoice, which refuses once money is received. */
    private void reverseInvoiceLedger(ClientInvoice invoice) {
        reverseInvoiceLedger(invoice, BigDecimal.ZERO, GlReferenceType.INVOICE_CANCEL, "cancelled");
    }

    private void reverseInvoiceLedger(ClientInvoice invoice, BigDecimal alreadyPaid,
                                       GlReferenceType referenceType, String reasonWord) {
        Long companyId = invoice.getCompanyId();
        String description = "Invoice " + invoice.getInvoiceNumber() + " " + reasonWord + " - reversal";

        ChartOfAccount ar = accountResolver.accountsReceivable(companyId);
        ChartOfAccount revenue = accountResolver.salesRevenue(companyId);

        BigDecimal revenueBase = toBase(invoice, recognizedRevenue(invoice));
        BigDecimal taxBase = invoice.getTaxAmount() != null && invoice.getTaxAmount().compareTo(BigDecimal.ZERO) > 0
                ? toBase(invoice, invoice.getTaxAmount()) : BigDecimal.ZERO;

        List<LedgerLine> lines = new java.util.ArrayList<>();
        lines.add(LedgerLine.credit(ar.getId(), revenueBase.add(taxBase)));
        lines.add(LedgerLine.debit(revenue.getId(), revenueBase));

        if (taxBase.compareTo(BigDecimal.ZERO) > 0) {
            ChartOfAccount tax = accountResolver.taxPayable(companyId);
            lines.add(LedgerLine.debit(tax.getId(), taxBase));
        }

        if (alreadyPaid != null && alreadyPaid.compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal paidBase = toBase(invoice, alreadyPaid);
            ChartOfAccount cash = accountResolver.cash(companyId);
            lines.add(LedgerLine.credit(cash.getId(), paidBase));
            lines.add(LedgerLine.debit(ar.getId(), paidBase));
        }

        // Undo credit notes already posted (Dr Revenue / Cr AR), else the blanket totalAmount reversal double-reduces AR for that portion.
        BigDecimal credited = invoice.getCreditedAmount() != null ? invoice.getCreditedAmount() : BigDecimal.ZERO;
        if (credited.compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal creditedBase = toBase(invoice, credited);
            lines.add(LedgerLine.credit(revenue.getId(), creditedBase));
            lines.add(LedgerLine.debit(ar.getId(), creditedBase));
        }

        glService.recordBalancedTransaction(companyId, lines, description,
                referenceType, invoice.getId(), invoice.getInvoiceNumber(), LocalDate.now());
    }

    @Override
    @Transactional
    public void cancelOrRefundForServiceRequest(Long companyId, Long invoiceId) {
        closeForServiceRequest(companyId, invoiceId, InvoiceStatus.CANCELLED);
    }

    @Override
    @Transactional
    public void voidSupersededForServiceRequest(Long companyId, Long invoiceId) {
        closeForServiceRequest(companyId, invoiceId, InvoiceStatus.VOIDED);
    }

    /** Shared by the service-request cancel path (-> CANCELLED) and the quotation-replacement path (-> VOIDED) so reports can tell them apart; the ledger reversal is identical. */
    private void closeForServiceRequest(Long companyId, Long invoiceId, InvoiceStatus closedStatus) {
        ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(invoiceId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + invoiceId));

        if (CLOSED_STATUSES.contains(invoice.getStatus())) {
            return; // nothing to do
        }

        if (hasPayments(invoice)) {
            // Money already collected needs staff review, not an instant reversal that credits Cash for money never handed back.
            if (refundRepository.existsByClientInvoiceIdAndCompanyIdAndStatus(invoiceId, companyId, RefundStatus.REQUESTED)) {
                return; // already has a pending refund request
            }
            Refund refund = Refund.builder()
                    .companyId(companyId)
                    .clientInvoice(invoice)
                    .requestedAmount(invoice.getPaidAmount())
                    .status(RefundStatus.REQUESTED)
                    .refundToWallet(Boolean.FALSE)
                    .build();
            refundRepository.save(refund);
            return;
        }

        boolean wasPosted = isRevenuePosted(invoice);
        invoice.setStatus(closedStatus);
        invoiceRepository.save(invoice);
        if (wasPosted) {
            reverseInvoiceLedger(invoice, BigDecimal.ZERO, GlReferenceType.INVOICE_CANCEL,
                    closedStatus == InvoiceStatus.VOIDED ? "voided (superseded)" : "cancelled");
        }
    }

    @Override
    @Transactional
    public RefundResponse requestRefund(Long invoiceId, RefundCreateRequest request) {
        authorizationService.checkPermission(PermissionCode.INVOICE_REFUND);
        Long companyId = requireCompanyId();
        ClientInvoice invoice = findInTenant(invoiceId);

        if (CLOSED_STATUSES.contains(invoice.getStatus()) || invoice.getStatus() == InvoiceStatus.DRAFT
                || !hasPayments(invoice)) {
            throw new BadRequestException("A refund can only be requested against a paid or partially paid invoice");
        }
        BigDecimal amount = request.getAmount();
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Refund amount must be positive");
        }
        if (amount.compareTo(invoice.getPaidAmount()) > 0) {
            throw new BadRequestException("Refund amount exceeds the amount paid on this invoice ("
                    + invoice.getPaidAmount() + ")");
        }
        if (refundRepository.existsByClientInvoiceIdAndCompanyIdAndStatus(invoiceId, companyId, RefundStatus.REQUESTED)) {
            throw new BadRequestException("This invoice already has a pending refund request - process or reject it first");
        }
        boolean toWallet = Boolean.TRUE.equals(request.getToWallet());
        if (toWallet) {
            requireWalletCurrency(companyId, invoice);
        }

        Refund refund = refundRepository.save(Refund.builder()
                .companyId(companyId)
                .clientInvoice(invoice)
                .requestedAmount(amount)
                .reason(request.getReason())
                .status(RefundStatus.REQUESTED)
                .refundToWallet(toWallet)
                .build());
        return RefundMapper.toResponse(refund);
    }

    /** The wallet holds a single currency; crediting invoice-currency units into it would mix currencies. */
    private void requireWalletCurrency(Long companyId, ClientInvoice invoice) {
        String walletCurrency = walletRepository.findByContextTypeAndContextId("COMPANY", companyId)
                .map(w -> w.getCurrency())
                .orElse("BDT");
        String invoiceCurrency = invoice.getCurrency() != null ? invoice.getCurrency() : "BDT";
        if (walletCurrency == null || !walletCurrency.equalsIgnoreCase(invoiceCurrency)) {
            throw new BadRequestException("Cannot refund to the wallet: the invoice is in " + invoiceCurrency
                    + " but the wallet holds " + walletCurrency + " - refund it externally instead");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Page<RefundResponse> listRefunds(RefundStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        Long companyId = requireCompanyId();
        Page<Refund> page = status != null
                ? refundRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                : refundRepository.findByCompanyId(companyId, pageable);
        return page.map(RefundMapper::toResponse);
    }

    @Override
    @Transactional
    public void processRefund(Long refundId) {
        authorizationService.checkPermission(PermissionCode.INVOICE_REFUND);
        Long companyId = requireCompanyId();
        Refund refund = refundRepository.findByIdAndCompanyId(refundId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Refund request not found: " + refundId));

        if (refund.getStatus() != RefundStatus.REQUESTED) {
            throw new BadRequestException("Only a requested refund can be processed");
        }

        ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(refund.getClientInvoice().getId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found"));
        if (CLOSED_STATUSES.contains(invoice.getStatus()) || invoice.getStatus() == InvoiceStatus.DRAFT
                || !hasPayments(invoice)) {
            throw new BadRequestException("Invoice is no longer in a paid state");
        }
        BigDecimal amount = refund.getRequestedAmount();
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Refund amount must be positive");
        }
        if (amount.compareTo(invoice.getPaidAmount()) > 0) {
            throw new BadRequestException("Refund amount " + amount + " exceeds the amount now paid on the invoice ("
                    + invoice.getPaidAmount() + ")");
        }
        boolean toWallet = Boolean.TRUE.equals(refund.getRefundToWallet());
        if (toWallet) {
            requireWalletCurrency(companyId, invoice);
        }

        if (amount.compareTo(invoice.getPaidAmount()) == 0) {
            // Everything received goes back: reverse revenue/AR/tax plus Cash for the paid amount, and close as REFUNDED.
            reverseInvoiceLedger(invoice, invoice.getPaidAmount(), GlReferenceType.INVOICE_REFUND, "refunded");
            invoice.setStatus(InvoiceStatus.REFUNDED);
        } else {
            // Invoice stays open and the refunded part is written down, not re-owed: paid -= amount, credited += amount leaves balance and status unchanged. Dr Sales Revenue / Cr Cash.
            BigDecimal amountBase = toBase(invoice, amount);
            ChartOfAccount revenue = accountResolver.salesRevenue(companyId);
            ChartOfAccount cash = accountResolver.cash(companyId);
            glService.recordBalancedTransaction(companyId, List.of(
                            LedgerLine.debit(revenue.getId(), amountBase),
                            LedgerLine.credit(cash.getId(), amountBase)),
                    "Partial refund on invoice " + invoice.getInvoiceNumber(),
                    GlReferenceType.INVOICE_REFUND, invoice.getId(), invoice.getInvoiceNumber(), LocalDate.now());
            invoice.setPaidAmount(invoice.getPaidAmount().subtract(amount));
            BigDecimal credited = invoice.getCreditedAmount() != null ? invoice.getCreditedAmount() : BigDecimal.ZERO;
            invoice.setCreditedAmount(credited.add(amount));
            invoice.calculateTotals();
        }
        invoiceRepository.save(invoice);

        refund.setStatus(RefundStatus.PROCESSED);
        refund.setProcessedBy(securityUtil.getCurrentUser());
        refund.setProcessedAt(LocalDateTime.now());
        refundRepository.save(refund);

        // A wallet refund additionally credits the company wallet, keyed by refund id so it can never be credited twice.
        if (toWallet) {
            walletService.creditOnce("COMPANY", companyId, amount, WalletTransactionType.REFUND_CREDIT,
                    "REFUND-" + refund.getId(),
                    "Refund for invoice " + invoice.getInvoiceNumber());
        }

        notifyClientOfRefundDecision(invoice, NotificationType.REFUND_PROCESSED, "Refund Processed",
                "Your refund of " + refund.getRequestedAmount() + " for invoice "
                        + invoice.getInvoiceNumber() + " has been processed"
                        + (toWallet ? " as wallet credit." : "."));
    }

    @Override
    @Transactional
    public void rejectRefund(Long refundId, String reason) {
        authorizationService.checkPermission(PermissionCode.INVOICE_REFUND);
        Long companyId = requireCompanyId();
        Refund refund = refundRepository.findByIdAndCompanyId(refundId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Refund request not found: " + refundId));

        if (refund.getStatus() != RefundStatus.REQUESTED) {
            throw new BadRequestException("Only a requested refund can be rejected");
        }

        refund.setStatus(RefundStatus.REJECTED);
        refund.setRejectionReason(reason);
        refundRepository.save(refund);

        notifyClientOfRefundDecision(refund.getClientInvoice(), NotificationType.REFUND_REJECTED, "Refund Rejected",
                "Your refund request for invoice " + refund.getClientInvoice().getInvoiceNumber()
                        + " was rejected." + (reason != null && !reason.isBlank() ? " Reason: " + reason : ""));
    }

    private void notifyClientOfRefundDecision(ClientInvoice invoice, NotificationType type, String title, String message) {
        try {
            Client client = invoice.getClient();
            if (client != null && client.getUser() != null) {
                notificationService.send(CreateNotificationRequest.of(
                        type, title, message, "/client/payments", client.getUser().getId(), invoice.getCompanyId()));
            }
        } catch (Exception ex) {
            // Notification failure must not roll back the refund decision itself.
        }
    }

    @Override
    @Transactional
    public CreditNoteResponse issueCreditNote(CreditNoteRequest request) {
        authorizationService.checkPermission(PermissionCode.INVOICE_CREDIT_NOTE);
        Long companyId = requireCompanyId();
        ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(request.getClientInvoiceId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + request.getClientInvoiceId()));

        if (invoice.getStatus() == InvoiceStatus.DRAFT || invoice.getStatus() == InvoiceStatus.CANCELLED
                || invoice.getStatus() == InvoiceStatus.VOIDED || invoice.getStatus() == InvoiceStatus.REFUNDED) {
            throw new BadRequestException("Cannot issue a credit note against a " + invoice.getStatus() + " invoice");
        }

        BigDecimal alreadyCredited = invoice.getCreditedAmount() != null ? invoice.getCreditedAmount() : BigDecimal.ZERO;
        BigDecimal outstanding = invoice.getTotalAmount().subtract(invoice.getPaidAmount()).subtract(alreadyCredited);
        if (request.getAmount().compareTo(outstanding) > 0) {
            throw new BadRequestException("Credit note amount exceeds the invoice's outstanding balance ("
                    + outstanding + ")");
        }

        LocalDateTime issuedAt = LocalDateTime.now();
        CreditNote creditNote = CreditNote.builder()
                .companyId(companyId)
                .creditNoteNumber(generateCreditNoteNumber(companyId, issuedAt.toLocalDate()))
                .clientInvoice(invoice)
                .amount(request.getAmount())
                .reason(request.getReason())
                .issuedBy(securityUtil.getCurrentUser())
                .issuedAt(issuedAt)
                .build();
        creditNoteRepository.save(creditNote);

        invoice.setCreditedAmount(alreadyCredited.add(request.getAmount()));
        invoice.calculateTotals();
        // calculateTotals() zeroes balanceAmount but not status, and the overdue scheduler checks only status, so a fully-credited invoice kept flipping to OVERDUE.
        if (invoice.getBalanceAmount().compareTo(BigDecimal.ZERO) <= 0
                && invoice.getStatus() != InvoiceStatus.PAID) {
            invoice.setStatus(InvoiceStatus.PAID);
            if (invoice.getPaidDate() == null) invoice.setPaidDate(LocalDate.now());
        }
        invoiceRepository.save(invoice);

        // Dr Sales Revenue / Cr Accounts Receivable: less revenue recognized and less owed, but no cash moves.
        String description = "Credit note " + creditNote.getCreditNoteNumber() + " for invoice " + invoice.getInvoiceNumber();
        BigDecimal creditBase = toBase(invoice, request.getAmount());
        ChartOfAccount revenue = accountResolver.salesRevenue(companyId);
        ChartOfAccount ar = accountResolver.accountsReceivable(companyId);
        glService.recordBalancedTransaction(companyId, List.of(
                        LedgerLine.debit(revenue.getId(), creditBase),
                        LedgerLine.credit(ar.getId(), creditBase)),
                description, GlReferenceType.INVOICE_CREDIT_NOTE, invoice.getId(), creditNote.getCreditNoteNumber(), LocalDate.now());

        return CreditNoteMapper.toResponse(creditNote);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<CreditNoteResponse> listCreditNotes(Long invoiceId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.INVOICE_VIEW);
        Long companyId = requireCompanyId();
        Page<CreditNote> page = invoiceId != null
                ? creditNoteRepository.findByCompanyIdAndClientInvoiceId(companyId, invoiceId, pageable)
                : creditNoteRepository.findByCompanyId(companyId, pageable);
        return page.map(CreditNoteMapper::toResponse);
    }

    /** CN-YYYY-NNNNNN from the locked DocumentNumberService counter, seeded from the highest number already used, soft-deleted credit notes included. */
    private String generateCreditNoteNumber(Long companyId, LocalDate issueDate) {
        int year = issueDate.getYear();
        String prefix = "CN-" + year + "-";
        return documentNumberService.next(companyId, DOC_TYPE_CREDIT_NOTE, year, prefix, () -> {
            Long max = creditNoteRepository.findMaxCreditNoteSequenceIncludingDeleted(companyId, prefix, prefix.length() + 1);
            return max == null ? 1L : max + 1L;
        });
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.INVOICE_DELETE);
        ClientInvoice invoice = findInTenant(id);  // tenant-scoped
        if (invoice.getStatus() != InvoiceStatus.DRAFT) {
            throw new com.zuhoocms.shared.exception.BadRequestException(
                    "Only DRAFT invoices can be deleted - use cancel for an already-sent invoice");
        }
        invoice.softDelete();
        invoiceRepository.save(invoice);
    }

    @Override
    @Transactional
    public void markAsOverdue(Long id) {
        ClientInvoice invoice = findInTenant(id);
        // Same eligibility as InvoiceOverdueScheduler: only open, issued invoices can become overdue.
        if (invoice.getStatus() == InvoiceStatus.ISSUED || invoice.getStatus() == InvoiceStatus.PARTIALLY_PAID) {
            invoice.setStatus(InvoiceStatus.OVERDUE);
            invoiceRepository.save(invoice);
        }
    }

    /** INV-YYYY-NNNNNN from the locked DocumentNumberService counter: read-MAX-then-insert raced and missed soft-deleted invoices still holding their number under the unique constraint. */
    private String generateInvoiceNumber(Long companyId, LocalDate invoiceDate) {
        int year = invoiceDate.getYear();
        String prefix = "INV-" + year + "-";
        return documentNumberService.next(companyId, DOC_TYPE_INVOICE, year, prefix, () -> {
            Long max = invoiceRepository.findMaxInvoiceSequenceIncludingDeleted(companyId, prefix, prefix.length() + 1);
            return max == null ? 1L : max + 1L;
        });
    }
}
