package com.zuhoocms.shared.payment.gateway;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.InvoiceStatus;
import com.zuhoocms.enums.WalletTransactionType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.company.CompanyService;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceService;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscription;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscriptionRepository;
import com.zuhoocms.modules.servicedesk.companyservice.ServicePackageService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.payment.wallet.WalletService;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinition;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinitionRepository;
import com.zuhoocms.shared.webhook.WebhookLog;
import com.zuhoocms.shared.webhook.WebhookLogRepository;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings("deprecation")
public class SslCommerzServiceImpl implements SslCommerzService {

    /** Invoices that can no longer take a gateway payment. */
    private static final Set<InvoiceStatus> UNPAYABLE_INVOICE_STATUSES = EnumSet.of(
        InvoiceStatus.PAID, InvoiceStatus.CANCELLED, InvoiceStatus.VOIDED, InvoiceStatus.REFUNDED);

    private final SslCommerzProperties properties;
    private final PaymentGatewayTransactionRepository transactionRepository;
    private final WebhookLogRepository webhookLogRepository;
    private final ClientInvoiceService invoiceService;
    private final ClientInvoiceRepository invoiceRepository;
    private final WalletService walletService;
    private final ServicePackageService packageService;
    private final PackageSubscriptionRepository subscriptionRepository;
    private final CompanyRepository companyRepository;
    private final CompanyService companyService;
    private final SubscriptionPlanDefinitionRepository subscriptionPlanDefinitionRepository;
    private final SecurityUtil securityUtil;
    private final ObjectMapper objectMapper;
    private final PlatformTransactionManager transactionManager;

    private final RestClient restClient = RestClient.create();

    @Value("${app.backend-url:http://localhost:8085}")
    private String backendUrl;

    @Override
    @Transactional
    public String initiate(GatewayPurpose purpose, Long targetId, BigDecimal amount) {
        if (properties.getStoreId() == null || properties.getStoreId().isBlank()) {
            throw new BadRequestException("Online payments are not configured (sslcommerz.store-id missing)");
        }
        if (purpose == null) {
            throw new BadRequestException("Purpose is required");
        }
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Amount must be greater than zero");
        }
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context");
        }
        User user = securityUtil.getCurrentUser();
        validateTarget(purpose, targetId, companyId, user, amount);

        // A platform plan upgrade must never be priced by the caller - always charge the catalog price.
        BigDecimal effectiveAmount = purpose == GatewayPurpose.PLATFORM_SUBSCRIPTION
            ? decodePlan(targetId).getPrice()
            : amount;
        if (effectiveAmount == null || effectiveAmount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Amount must be greater than zero");
        }

        String tranId = "BOS-" + UUID.randomUUID().toString().replace("-", "").substring(0, 24);

        PaymentGatewayTransaction tx = PaymentGatewayTransaction.builder()
            .tranId(tranId)
            .purpose(purpose)
            .targetId(targetId)
            .companyId(companyId)
            .initiatedByUserId(user != null ? user.getId() : null)
            .amount(effectiveAmount)
            .currency(properties.getCurrency())
            .status(GatewayTransactionStatus.INITIATED)
            .initiatedAt(LocalDateTime.now())
            .build();
        transactionRepository.save(tx);

        String cb = backendUrl + "/api/payments/sslcommerz/callback";
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("store_id", properties.getStoreId());
        form.add("store_passwd", properties.getStorePassword());
        form.add("total_amount", effectiveAmount.toPlainString());
        form.add("currency", properties.getCurrency());
        form.add("tran_id", tranId);
        form.add("success_url", cb + "/success");
        form.add("fail_url", cb + "/fail");
        form.add("cancel_url", cb + "/cancel");
        form.add("ipn_url", backendUrl + "/api/payments/sslcommerz/ipn");
        form.add("product_category", purpose.name());
        form.add("product_name", purpose.name() + (targetId != null ? "-" + targetId : ""));
        form.add("product_profile", "non-physical-goods");
        form.add("shipping_method", "NO");
        // SSLCommerz requires customer fields; use what we have
        form.add("cus_name", user != null ? user.getEmail() : "customer");
        form.add("cus_email", user != null ? user.getEmail() : "customer@example.com");
        form.add("cus_add1", "N/A");
        form.add("cus_city", "N/A");
        form.add("cus_country", "Bangladesh");
        form.add("cus_phone", "N/A");

        try {
            String body = restClient.post()
                .uri(properties.initiateUrl())
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(String.class);
            JsonNode json = objectMapper.readTree(body);
            if (!"SUCCESS".equalsIgnoreCase(json.path("status").asText())) {
                log.error("SSLCommerz initiate failed: {}", json.path("failedreason").asText());
                throw new BadRequestException("Payment gateway rejected the request: "
                    + json.path("failedreason").asText("unknown reason"));
            }
            return json.path("GatewayPageURL").asText();
        } catch (BadRequestException e) {
            throw e;
        } catch (Exception e) {
            log.error("SSLCommerz initiate error", e);
            throw new BadRequestException("Could not reach the payment gateway. Try again later.");
        }
    }

    /**
     * A CLIENT may only pay their own target; otherwise any client could pay an arbitrary targetId in the same tenant.
     * Also checks the amount against the target: the gateway charges what is sent here, so an unabsorbable amount charges the customer for nothing.
     */
    private void validateTarget(GatewayPurpose purpose, Long targetId, Long companyId, User user, BigDecimal amount) {
        boolean isClient = user != null && user.getRole() == Role.CLIENT;

        switch (purpose) {
            case INVOICE -> {
                if (targetId == null) {
                    throw new BadRequestException("Invoice id is required");
                }
                ClientInvoice invoice = invoiceRepository.findByIdAndCompanyId(targetId, companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + targetId));
                if (isClient && !ownedByUser(invoice.getClient(), user)) {
                    throw new ForbiddenException("This invoice does not belong to you");
                }
                if (UNPAYABLE_INVOICE_STATUSES.contains(invoice.getStatus())) {
                    throw new BadRequestException("This invoice is " + invoice.getStatus().name().toLowerCase()
                        + " and cannot be paid online");
                }
                // The gateway charges in its configured currency but the charge is recorded in the invoice's currency.
                String gatewayCurrency = properties.getCurrency();
                String invoiceCurrency = invoice.getCurrency() != null ? invoice.getCurrency() : "BDT";
                if (gatewayCurrency == null || !gatewayCurrency.equalsIgnoreCase(invoiceCurrency)) {
                    throw new BadRequestException("This invoice is in " + invoiceCurrency
                        + ", but online payments are only available in " + gatewayCurrency
                        + ". Please pay it by another method.");
                }
                BigDecimal paid = invoice.getPaidAmount() != null ? invoice.getPaidAmount() : BigDecimal.ZERO;
                BigDecimal credited = invoice.getCreditedAmount() != null ? invoice.getCreditedAmount() : BigDecimal.ZERO;
                BigDecimal balance = invoice.getTotalAmount().subtract(paid).subtract(credited);
                if (amount.compareTo(balance) > 0) {
                    throw new BadRequestException("Amount " + amount.toPlainString()
                        + " exceeds the invoice's outstanding balance of " + balance.toPlainString());
                }
            }
            case PACKAGE_SUBSCRIPTION -> {
                if (targetId == null) {
                    throw new BadRequestException("Subscription id is required");
                }
                PackageSubscription subscription = subscriptionRepository
                    .findByIdAndCompanyId(targetId, companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Subscription not found: " + targetId));
                if (isClient && !ownedByUser(subscription.getClient(), user)) {
                    throw new ForbiddenException("This subscription does not belong to you");
                }
                BigDecimal price = subscription.getPricePaid();
                if (price == null || amount.compareTo(price) != 0) {
                    throw new BadRequestException("Amount must equal the subscription price"
                        + (price != null ? " of " + price.toPlainString() : ""));
                }
            }
            case WALLET_TOPUP -> {
                // Credits the company's shared wallet - no per-target ownership beyond companyId scoping.
            }
            case PLATFORM_SUBSCRIPTION -> {
                if (user == null || user.getRole() != Role.COMPANY_OWNER) {
                    throw new ForbiddenException("Only the company owner can change the subscription plan");
                }
                SubscriptionPlanDefinition targetPlan = decodePlan(targetId);
                Company company = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                BigDecimal currentPrice = subscriptionPlanDefinitionRepository
                    .findByCode(company.getSubscriptionPlan())
                    .map(SubscriptionPlanDefinition::getPrice)
                    .orElse(BigDecimal.ZERO);
                if (targetPlan.getPrice().compareTo(currentPrice) <= 0) {
                    throw new BadRequestException("You can only upgrade to a higher-priced plan than your current one");
                }
            }
        }
    }

    /** InitiateGatewayPaymentRequest.targetId is the SubscriptionPlanDefinition's own id. */
    private SubscriptionPlanDefinition decodePlan(Long targetId) {
        if (targetId == null) {
            throw new BadRequestException("Invalid subscription plan");
        }
        return subscriptionPlanDefinitionRepository.findById(targetId)
            .filter(SubscriptionPlanDefinition::isActive)
            .orElseThrow(() -> new BadRequestException("Invalid subscription plan"));
    }

    private boolean ownedByUser(com.zuhoocms.modules.crm.client.Client client, User user) {
        return client != null && client.getUser() != null && client.getUser().getId().equals(user.getId());
    }

    /**
     * Success callback / IPN: verify signature, record the confirmed charge, then apply it - each step commits on its own.
     * Not @Transactional: as one transaction an apply failure rolled back the SUCCESS marker, leaving INITIATED after a real charge.
     * A failed apply leaves the row SUCCESS with applied = false for GatewayApplyRetryScheduler.
     */
    @Override
    public GatewayTransactionStatus handleSuccess(Map<String, String> params) {
        String tranId = params.get("tran_id");

        if (!SslCommerzSignature.isValid(params, properties.getStorePassword())) {
            log.warn("SSLCommerz callback rejected: verify_sign missing or invalid (tran_id={})", tranId);
            return GatewayTransactionStatus.VALIDATION_FAILED;
        }

        String valId = params.get("val_id");
        logWebhook(params);

        PaymentGatewayTransaction snapshot = transactionRepository.findByTranId(tranId)
            .orElseThrow(() -> new ResourceNotFoundException("Unknown transaction: " + tranId));

        // Idempotency: success callback AND IPN both land here
        if (snapshot.getStatus() == GatewayTransactionStatus.SUCCESS) {
            return GatewayTransactionStatus.SUCCESS;
        }

        // Network call made without holding the row lock.
        GatewayValidation validation = validateWithGateway(snapshot, valId);

        GatewayTransactionStatus recorded;
        try {
            recorded = requiresNew().execute(status -> recordValidation(tranId, valId, params, validation));
        } catch (DataIntegrityViolationException e) {
            // uq_pgt_val_id: a concurrent callback settled another row with the same val_id.
            log.warn("SSLCommerz val_id {} already settles another transaction - {} rejected", valId, tranId);
            return GatewayTransactionStatus.VALIDATION_FAILED;
        }
        if (recorded != GatewayTransactionStatus.SUCCESS) {
            return recorded;
        }

        applyConfirmedTransaction(tranId);
        // The charge is recorded either way; an apply failure is retried and does not fail the customer's payment.
        return GatewayTransactionStatus.SUCCESS;
    }

    /** Step 2: runs in its own transaction with the row locked. */
    private GatewayTransactionStatus recordValidation(String tranId, String valId, Map<String, String> params,
                                                      GatewayValidation validation) {
        PaymentGatewayTransaction tx = transactionRepository.findByTranIdForUpdate(tranId)
            .orElseThrow(() -> new ResourceNotFoundException("Unknown transaction: " + tranId));
        if (tx.getStatus() == GatewayTransactionStatus.SUCCESS) {
            return GatewayTransactionStatus.SUCCESS; // a concurrent callback got here first
        }
        if (!validation.ok()) {
            tx.setStatus(GatewayTransactionStatus.VALIDATION_FAILED);
            tx.setValidationStatus(truncate(validation.status(), 30));
            tx.setValidatedAt(LocalDateTime.now());
            transactionRepository.save(tx);
            return GatewayTransactionStatus.VALIDATION_FAILED;
        }
        if (transactionRepository.existsByValIdAndIdNot(valId, tx.getId())) {
            log.warn("SSLCommerz val_id {} already settled another transaction; {} not accepted", valId, tranId);
            tx.setStatus(GatewayTransactionStatus.VALIDATION_FAILED);
            tx.setValidationStatus("DUPLICATE_VAL_ID");
            tx.setValidatedAt(LocalDateTime.now());
            transactionRepository.save(tx);
            return GatewayTransactionStatus.VALIDATION_FAILED;
        }

        LocalDateTime now = LocalDateTime.now();
        tx.setStatus(GatewayTransactionStatus.SUCCESS);
        tx.setValId(valId);
        tx.setBankTranId(params.get("bank_tran_id"));
        tx.setCardType(params.get("card_type"));
        tx.setCompletedAt(now);
        tx.setValidationStatus(truncate(validation.status(), 30));
        tx.setValidatedAmount(validation.amount());
        tx.setValidatedAt(now);
        tx.setApplied(Boolean.FALSE);
        tx.setApplyAttempts(0);
        transactionRepository.saveAndFlush(tx);
        return GatewayTransactionStatus.SUCCESS;
    }

    /** Applies a recorded, not-yet-applied charge in its own transaction; on failure records the error in yet another one. */
    @Override
    public boolean applyConfirmedTransaction(String tranId) {
        try {
            Boolean applied = requiresNew().execute(status -> {
                PaymentGatewayTransaction tx = transactionRepository.findByTranIdForUpdate(tranId).orElse(null);
                if (tx == null || tx.getStatus() != GatewayTransactionStatus.SUCCESS
                        || !Boolean.FALSE.equals(tx.getApplied())) {
                    return false; // unknown, not confirmed, already applied, or a legacy row
                }
                applyToDomain(tx);
                tx.setApplied(Boolean.TRUE);
                tx.setAppliedAt(LocalDateTime.now());
                tx.setApplyError(null);
                tx.setApplyAttempts((tx.getApplyAttempts() == null ? 0 : tx.getApplyAttempts()) + 1);
                tx.setLastApplyAttemptAt(LocalDateTime.now());
                transactionRepository.save(tx);
                return true;
            });
            return Boolean.TRUE.equals(applied);
        } catch (Exception e) {
            log.error("SSLCommerz transaction {} was charged but could not be applied: {}", tranId, e.getMessage());
            try {
                requiresNew().executeWithoutResult(status ->
                    transactionRepository.findByTranIdForUpdate(tranId).ifPresent(tx -> {
                        if (Boolean.FALSE.equals(tx.getApplied())) {
                            tx.setApplyError(truncate(e.getClass().getSimpleName() + ": " + e.getMessage(), 1000));
                            tx.setApplyAttempts((tx.getApplyAttempts() == null ? 0 : tx.getApplyAttempts()) + 1);
                            tx.setLastApplyAttemptAt(LocalDateTime.now());
                            transactionRepository.save(tx);
                        }
                    }));
            } catch (Exception recordError) {
                log.error("Could not record the apply failure for {}: {}", tranId, recordError.getMessage());
            }
            return false;
        }
    }

    /** Applies to the domain object using the companyId captured at initiate time - callbacks have no security context. */
    private void applyToDomain(PaymentGatewayTransaction tx) {
        switch (tx.getPurpose()) {
            case INVOICE -> invoiceService.recordPaymentForCompany(
                tx.getCompanyId(), tx.getTargetId(), tx.getAmount());
            case WALLET_TOPUP -> walletService.credit(
                "COMPANY", tx.getCompanyId(), tx.getAmount(),
                WalletTransactionType.CREDIT, tx.getTranId(), "SSLCommerz top-up");
            case PACKAGE_SUBSCRIPTION -> packageService.activateForCompany(
                tx.getCompanyId(), tx.getTargetId());
            case PLATFORM_SUBSCRIPTION -> companyService.applyPaidPlanUpgrade(
                tx.getCompanyId(), decodePlan(tx.getTargetId()), tx.getAmount(),
                tx.getTranId(), tx.getInitiatedByUserId());
        }
    }

    private TransactionTemplate requiresNew() {
        TransactionTemplate template = new TransactionTemplate(transactionManager);
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return template;
    }

    record GatewayValidation(boolean ok, String status, BigDecimal amount) {
    }

    /** Server-side validation: must be VALID/VALIDATED for this exact tran_id, amount and currency - a genuine val_id from a cheaper checkout used to be accepted for any tran_id. */
    private GatewayValidation validateWithGateway(PaymentGatewayTransaction tx, String valId) {
        if (valId == null || valId.isBlank()) return new GatewayValidation(false, "MISSING_VAL_ID", null);
        try {
            String url = UriComponentsBuilder.fromUriString(properties.validationUrl())
                .queryParam("val_id", valId)
                .queryParam("store_id", properties.getStoreId())
                .queryParam("store_passwd", properties.getStorePassword())
                .queryParam("format", "json")
                .encode()
                .toUriString();
            String body = restClient.get().uri(java.net.URI.create(url)).retrieve().body(String.class);
            JsonNode json = objectMapper.readTree(body);
            String status = json.path("status").asText();
            boolean statusOk = "VALID".equalsIgnoreCase(status) || "VALIDATED".equalsIgnoreCase(status);
            BigDecimal validatedAmount = parseAmount(json.path("amount").asText("0"));
            boolean amountOk = validatedAmount != null && tx.getAmount().compareTo(validatedAmount) == 0;
            boolean currencyOk = tx.getCurrency() != null
                && tx.getCurrency().equalsIgnoreCase(json.path("currency").asText(""));
            boolean tranIdOk = tx.getTranId().equals(json.path("tran_id").asText(""));
            if (!statusOk || !amountOk || !currencyOk || !tranIdOk) {
                log.warn("SSLCommerz validation mismatch for {}: status={} amountOk={} currencyOk={} tranIdOk={}",
                    tx.getTranId(), status, amountOk, currencyOk, tranIdOk);
            }
            String recordedStatus = tranIdOk ? status : "TRAN_ID_MISMATCH";
            return new GatewayValidation(statusOk && amountOk && currencyOk && tranIdOk, recordedStatus, validatedAmount);
        } catch (Exception e) {
            log.error("SSLCommerz validation error for {}", tx.getTranId(), e);
            return new GatewayValidation(false, "VALIDATION_ERROR", null);
        }
    }

    private static BigDecimal parseAmount(String raw) {
        try {
            return new BigDecimal(raw.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String truncate(String value, int max) {
        if (value == null) return null;
        return value.length() <= max ? value : value.substring(0, max);
    }

    @Override
    @Transactional
    public void markFailed(String tranId) {
        transactionRepository.findByTranId(tranId).ifPresent(tx -> {
            if (tx.getStatus() == GatewayTransactionStatus.INITIATED) {
                tx.setStatus(GatewayTransactionStatus.FAILED);
                tx.setCompletedAt(LocalDateTime.now());
                transactionRepository.save(tx);
            }
        });
    }

    @Override
    @Transactional
    public void markCancelled(String tranId) {
        transactionRepository.findByTranId(tranId).ifPresent(tx -> {
            if (tx.getStatus() == GatewayTransactionStatus.INITIATED) {
                tx.setStatus(GatewayTransactionStatus.CANCELLED);
                tx.setCompletedAt(LocalDateTime.now());
                transactionRepository.save(tx);
            }
        });
    }

    private void logWebhook(Map<String, String> params) {
        try {
            WebhookLog wl = new WebhookLog();
            wl.setProvider("SSLCOMMERZ");
            wl.setEventType("PAYMENT_CALLBACK");
            wl.setTransactionId(params.get("tran_id"));
            wl.setPayload(objectMapper.writeValueAsString(params));
            webhookLogRepository.save(wl);
        } catch (Exception e) {
            log.warn("Could not persist webhook log: {}", e.getMessage());
        }
    }
}
