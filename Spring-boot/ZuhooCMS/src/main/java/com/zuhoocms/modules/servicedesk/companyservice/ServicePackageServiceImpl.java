package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.enums.SubscriptionStatus;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceItemRequest;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRequest;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceResponse;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceService;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor

public class ServicePackageServiceImpl implements ServicePackageService {

    private final ServicePackageRepository     packageRepository;
    private final PackageSubscriptionRepository subscriptionRepository;
    private final CompanyServiceRepository     companyServiceRepository;
    private final ClientRepository             clientRepository;
    private final SecurityUtil                 securityUtil;
    private final AuthorizationService         authorizationService;
    private final ClientInvoiceService         invoiceService;

    @Override
    @Transactional
    public ServicePackageResponse create(ServicePackageRequest request) {
        // Creating a package was open to anyone: the list beside it checks SERVICE_PACKAGE_VIEW while
        // create, update, toggle and delete checked nothing, so an employee who could not list packages
        // could still create and reprice them.
        authorizationService.checkPermission(PermissionCode.SERVICE_PACKAGE_MANAGE);
        Long companyId = requireCompanyId();

        if (packageRepository.existsByCompanyIdAndName(companyId, request.getName())) {
            throw new BadRequestException(
                "A package named '" + request.getName() + "' already exists");
        }

        ServicePackage pkg = ServicePackage.builder()
            .name(request.getName())
            .nameBn(request.getNameBn())
            .description(request.getDescription())
            .descriptionBn(request.getDescriptionBn())
            .iconUrl(request.getIconUrl())
            .packagePrice(request.getPackagePrice())
            .discountPercent(request.getDiscountPercent() != null
                ? request.getDiscountPercent() : BigDecimal.ZERO)
            .billingCycle(request.getBillingCycle())
            .requestQuota(request.getRequestQuota())
            .autoRenew(request.getAutoRenew() != null ? request.getAutoRenew() : true)
            .active(true)
            .deliveryDays(request.getDeliveryDays())
            .terms(request.getTerms())
            .featured(Boolean.TRUE.equals(request.getFeatured()))
            .popular(Boolean.TRUE.equals(request.getPopular()))
            .company(companyRef(companyId))
            .services(new ArrayList<>())
            .build();

        if (request.getServiceIds() != null && !request.getServiceIds().isEmpty()) {
            List<CompanyService> services = resolveServices(
                request.getServiceIds(), companyId);
            pkg.getServices().addAll(services);
        }

        packageRepository.save(pkg);
        
        return ServicePackageMapper.toResponse(pkg);
    }

    @Override
    @Transactional(readOnly = true)
    public ServicePackageResponse getById(Long id) {
        return ServicePackageMapper.toResponse(findPackageInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServicePackageResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SERVICE_PACKAGE_VIEW);
        return packageRepository.findByCompanyId(requireCompanyId(), pageable)
            .map(ServicePackageMapper::toResponse);
    }

    // Deliberately not gated by SERVICE_PACKAGE_VIEW: CLIENT-role users have no CustomRole but must browse the active catalog to subscribe.
    @Override
    @Transactional(readOnly = true)
    public List<ServicePackageResponse> listActive() {
        return packageRepository.findByCompanyIdAndActiveTrue(requireCompanyId())
            .stream().map(ServicePackageMapper::toResponse).toList();
    }

    @Override
    @Transactional
    public ServicePackageResponse update(Long id, ServicePackageRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_PACKAGE_MANAGE);
        Long companyId = requireCompanyId();
        ServicePackage pkg = findPackageInTenant(id);

        if (!pkg.getName().equals(request.getName())
                && packageRepository.existsByCompanyIdAndNameAndIdNot(
                    companyId, request.getName(), id)) {
            throw new BadRequestException(
                "A package named '" + request.getName() + "' already exists");
        }

        if (request.getName()            != null) pkg.setName(request.getName());
        if (request.getNameBn()          != null) pkg.setNameBn(request.getNameBn());
        if (request.getDescription()     != null) pkg.setDescription(request.getDescription());
        if (request.getDescriptionBn()   != null) pkg.setDescriptionBn(request.getDescriptionBn());
        if (request.getIconUrl()         != null) pkg.setIconUrl(request.getIconUrl());
        // Applied unconditionally: a null packagePrice means "back to auto-calculated price" and must be able to clear a manual override.
        pkg.setPackagePrice(request.getPackagePrice());
        // Null-skipped, unlike packagePrice above. An absent discount used to be coerced to ZERO, so a package
        // edited from any screen that does not carry the field silently went back to full price - the response
        // returned 0 where 10 had been. Clearing a discount is still possible by sending 0 explicitly.
        if (request.getDiscountPercent() != null) {
            pkg.setDiscountPercent(request.getDiscountPercent());
        }
        if (request.getBillingCycle()    != null) pkg.setBillingCycle(request.getBillingCycle());
        if (request.getRequestQuota()    != null) pkg.setRequestQuota(request.getRequestQuota());
        if (request.getAutoRenew()       != null) pkg.setAutoRenew(request.getAutoRenew());
        if (request.getDeliveryDays()    != null) pkg.setDeliveryDays(request.getDeliveryDays());
        if (request.getTerms()           != null) pkg.setTerms(request.getTerms());
        if (request.getFeatured() != null) pkg.setFeatured(request.getFeatured());
        if (request.getPopular() != null) pkg.setPopular(request.getPopular());

        if (request.getServiceIds() != null) {
            pkg.getServices().clear();
            if (!request.getServiceIds().isEmpty()) {
                pkg.getServices().addAll(
                    resolveServices(request.getServiceIds(), companyId));
            }
        }

        packageRepository.save(pkg);
        return ServicePackageMapper.toResponse(pkg);
    }

    @Override
    @Transactional
    public ServicePackageResponse toggleActive(Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_PACKAGE_MANAGE);
        ServicePackage pkg = findPackageInTenant(id);
        pkg.setActive(!pkg.isActive());
        packageRepository.save(pkg);
        
        return ServicePackageMapper.toResponse(pkg);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_PACKAGE_MANAGE);
        ServicePackage pkg = findPackageInTenant(id);

        boolean hasActiveSubs = subscriptionRepository
            .existsByServicePackageIdAndStatus(id, SubscriptionStatus.ACTIVE);

        if (hasActiveSubs) {
            throw new BadRequestException(
                "Cannot delete a package that has active subscriptions. " +
                "Deactivate it instead.");
        }

        pkg.softDelete();
        packageRepository.save(pkg);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse subscribe(SubscribeRequest request) {
        Long companyId = requireCompanyId();

        ServicePackage pkg = findPackageInTenant(request.getPackageId());
        if (!pkg.isActive()) {
            throw new BadRequestException("This package is not currently available");
        }

        // CLIENT role resolves from JWT; admin passes clientId explicitly
        Client client = resolveClient(request.getClientId(), companyId);

        // One active subscription per package
        subscriptionRepository
            .findByCompanyIdAndClientIdAndServicePackageIdAndStatus(
                companyId, client.getId(), pkg.getId(), SubscriptionStatus.ACTIVE)
            .ifPresent(existing -> {
                throw new BadRequestException(
                    "Client already has an active subscription to this package");
            });

        LocalDate startDate = LocalDate.now();
        LocalDate endDate   = calculateEndDate(startDate, pkg.getBillingCycle());

        boolean autoRenew = request.getAutoRenew() != null
            ? request.getAutoRenew()
            : pkg.isAutoRenew();

        PackageSubscription subscription = PackageSubscription.builder()
            .servicePackage(pkg)
            .client(client)
            .company(companyRef(companyId))
            .status(SubscriptionStatus.PENDING_PAYMENT)
            .billingCycle(pkg.getBillingCycle())
            .startDate(startDate)
            .endDate(endDate)
            .nextBillingDate(endDate)
            .pricePaid(pkg.getEffectivePrice())
            .requestQuota(pkg.getRequestQuota())
            .requestsUsed(0)
            .autoRenew(autoRenew)
            .build();

        subscriptionRepository.save(subscription);
        
        return ServicePackageMapper.toSubscriptionResponse(subscription);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse activate(Long subscriptionId) {
        return activateForCompany(requireCompanyId(), subscriptionId);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse activateForCompany(Long companyId, Long subscriptionId) {
        PackageSubscription sub = subscriptionRepository.findByIdAndCompanyId(subscriptionId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Subscription not found: " + subscriptionId));

        if (sub.getStatus() != SubscriptionStatus.PENDING_PAYMENT) {
            throw new BadRequestException(
                "Only PENDING_PAYMENT subscriptions can be activated. " +
                "Current status: " + sub.getStatus());
        }

        sub.setStatus(SubscriptionStatus.ACTIVE);
        sub.setActivatedAt(LocalDateTime.now());
        subscriptionRepository.save(sub);

        
        return ServicePackageMapper.toSubscriptionResponse(sub);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse suspend(Long subscriptionId, String reason) {
        PackageSubscription sub = findSubscriptionInTenant(subscriptionId);

        if (sub.getStatus() != SubscriptionStatus.ACTIVE) {
            throw new BadRequestException(
                "Only ACTIVE subscriptions can be suspended. " +
                "Current status: " + sub.getStatus());
        }

        sub.setStatus(SubscriptionStatus.SUSPENDED);
        sub.setCancelledAt(LocalDateTime.now());
        sub.setCancellationReason(reason);
        subscriptionRepository.save(sub);

        
        return ServicePackageMapper.toSubscriptionResponse(sub);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse cancel(Long subscriptionId, String reason) {
        PackageSubscription sub = findSubscriptionInTenant(subscriptionId);

        if (sub.getStatus() == SubscriptionStatus.CANCELLED) {
            throw new BadRequestException("Subscription is already cancelled");
        }
        if (sub.getStatus() == SubscriptionStatus.EXPIRED) {
            throw new BadRequestException("Cannot cancel an expired subscription");
        }

        sub.setStatus(SubscriptionStatus.CANCELLED);
        sub.setCancelledAt(LocalDateTime.now());
        sub.setCancellationReason(reason);
        subscriptionRepository.save(sub);

        
        return ServicePackageMapper.toSubscriptionResponse(sub);
    }

    @Override
    @Transactional
    public PackageSubscriptionResponse reactivate(Long subscriptionId) {
        PackageSubscription sub = findSubscriptionInTenant(subscriptionId);

        if (sub.getStatus() != SubscriptionStatus.SUSPENDED) {
            throw new BadRequestException(
                "Only SUSPENDED subscriptions can be reactivated. " +
                "Current status: " + sub.getStatus());
        }

        sub.setStatus(SubscriptionStatus.ACTIVE);
        sub.setCancelledAt(null);
        sub.setCancellationReason(null);
        subscriptionRepository.save(sub);


        return ServicePackageMapper.toSubscriptionResponse(sub);
    }

    // System entry points (scheduler) — no security/tenant context, mirrors activateForCompany().

    @Override
    @Transactional
    public PackageSubscription renewSubscription(Long subscriptionId) {
        PackageSubscription sub = subscriptionRepository.findById(subscriptionId)
            .orElseThrow(() -> new ResourceNotFoundException("Subscription not found: " + subscriptionId));

        if (sub.getStatus() != SubscriptionStatus.ACTIVE) {
            throw new BadRequestException(
                "Only ACTIVE subscriptions can be renewed. Current status: " + sub.getStatus());
        }

        LocalDate today = LocalDate.now();
        if (sub.getEndDate() != null && !sub.getEndDate().isBefore(today)) {
            // Period is still current - nothing is due (keeps a re-run from renewing twice).
            return sub;
        }

        // Roll forward until the period covers today: from the old endDate alone, a scheduler that missed a week renewed one stale period per night, resetting requestsUsed each time.
        LocalDate newStart = sub.getEndDate() != null ? sub.getEndDate() : today;
        LocalDate newEnd = calculateEndDate(newStart, sub.getBillingCycle());
        if (newEnd == null) {
            throw new BadRequestException("ONE_TIME subscriptions cannot be renewed");
        }
        while (newEnd.isBefore(today)) {
            newStart = newEnd;
            newEnd = calculateEndDate(newStart, sub.getBillingCycle());
        }

        sub.setStartDate(newStart);
        sub.setEndDate(newEnd);
        sub.setNextBillingDate(newEnd);
        // Re-price from the package's current effective price, so price changes apply at the next renewal.
        sub.setPricePaid(sub.getServicePackage().getEffectivePrice());
        sub.setRequestsUsed(0);

        // Invoice the new period once, in the same transaction, so a failure rolls back the renewal and the next sweep retries it.
        raiseRenewalInvoice(sub, newStart, newEnd);

        subscriptionRepository.save(sub);
        return sub;
    }

    private void raiseRenewalInvoice(PackageSubscription sub, LocalDate periodStart, LocalDate periodEnd) {
        if (periodStart.equals(sub.getLastRenewalInvoicedPeriodStart())) {
            return; // already invoiced for this period
        }
        BigDecimal amount = sub.getPricePaid();
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            return;
        }
        Long companyId = sub.getCompany().getId();
        ServicePackage pkg = sub.getServicePackage();

        ClientInvoiceItemRequest item = ClientInvoiceItemRequest.builder()
            .description("Subscription renewal: " + pkg.getName() + " (" + periodStart + " to " + periodEnd + ")")
            .quantity(BigDecimal.ONE)
            .unitPrice(amount)
            .build();

        ClientInvoiceRequest invoiceRequest = ClientInvoiceRequest.builder()
            .clientId(sub.getClient().getId())
            .invoiceDate(LocalDate.now())
            .dueDate(LocalDate.now().plusDays(7))
            .currency(resolvePackageCurrency(pkg, sub.getCompany()))
            .notes("Auto-renewal of subscription #" + sub.getId() + " for " + periodStart + " to " + periodEnd)
            .items(List.of(item))
            .build();

        ClientInvoiceResponse invoice = invoiceService.createForServiceRequest(companyId, invoiceRequest);
        invoiceService.sendInvoiceForCompany(companyId, invoice.getId());

        sub.setLastRenewalInvoicedPeriodStart(periodStart);
        sub.setLastRenewalInvoiceId(invoice.getId());
    }

    /** A package has no currency of its own: use its services' currency when they agree, else the company's base. */
    private String resolvePackageCurrency(ServicePackage pkg, Company company) {
        List<String> currencies = pkg.getServices() == null ? List.of() : pkg.getServices().stream()
            .map(CompanyService::getCurrency)
            .filter(c -> c != null && !c.isBlank())
            .map(String::toUpperCase)
            .distinct()
            .toList();
        if (currencies.size() == 1) return currencies.get(0);
        return company != null ? company.getBaseCurrency() : null;
    }

    @Override
    @Transactional
    public PackageSubscription expireSubscription(Long subscriptionId) {
        PackageSubscription sub = subscriptionRepository.findById(subscriptionId)
            .orElseThrow(() -> new ResourceNotFoundException("Subscription not found: " + subscriptionId));

        if (sub.getStatus() != SubscriptionStatus.ACTIVE) {
            throw new BadRequestException(
                "Only ACTIVE subscriptions can be expired. Current status: " + sub.getStatus());
        }

        sub.setStatus(SubscriptionStatus.EXPIRED);
        sub.setCancelledAt(LocalDateTime.now());
        sub.setCancellationReason("Subscription period ended");
        subscriptionRepository.save(sub);
        return sub;
    }

    @Override
    @Transactional(readOnly = true)
    public PackageSubscriptionResponse getSubscriptionById(Long id) {
        return ServicePackageMapper.toSubscriptionResponse(findSubscriptionInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PackageSubscriptionResponse> listSubscriptions(
            SubscriptionStatus status, Pageable pageable) {
        Long companyId = requireCompanyId();
        Page<PackageSubscription> page = status != null
            ? subscriptionRepository.findByCompanyIdAndStatus(companyId, status, pageable)
            : subscriptionRepository.findByCompanyId(companyId, pageable);
        return page.map(ServicePackageMapper::toSubscriptionResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PackageSubscriptionResponse> listMySubscriptions(Pageable pageable) {
        Long companyId = requireCompanyId();
        Client client = clientRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .orElseThrow(() -> new BadRequestException("Client profile not found"));
        return subscriptionRepository
            .findByCompanyIdAndClientId(companyId, client.getId(), pageable)
            .map(ServicePackageMapper::toSubscriptionResponse);
    }

    @Override
    @Transactional
    public PackageSubscription consumeQuota(Long subscriptionId) {
        try {
            PackageSubscription sub = subscriptionRepository.findByIdAndCompanyIdForUpdate(subscriptionId, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Subscription not found: " + subscriptionId));

            if (!sub.isUsable()) {
                throw new BadRequestException(
                    "Subscription is not active or has expired");
            }
            if (!sub.hasRemainingQuota()) {
                // With an overage rate the request is allowed through; UsageBillingService invoices the extra unit on completion.
                if (sub.getServicePackage().getOverageRate() == null) {
                    throw new BadRequestException(
                        "Request quota exhausted for this subscription. " +
                        "Remaining: 0 of " + sub.getRequestQuota());
                }
            }

            sub.setRequestsUsed(sub.getRequestsUsed() + 1);
            subscriptionRepository.save(sub);
            return sub;
        } catch (org.springframework.dao.PessimisticLockingFailureException ex) {
            throw new BadRequestException("The subscription is currently being updated by another request. Please try again.", ex);
        }
    }

    @Override
    @Transactional
    public PackageSubscription releaseQuota(Long subscriptionId) {
        return releaseQuotaForCompany(requireCompanyId(), subscriptionId);
    }

    @Override
    @Transactional
    public PackageSubscription releaseQuotaForCompany(Long companyId, Long subscriptionId) {
        try {
            PackageSubscription sub = subscriptionRepository.findByIdAndCompanyIdForUpdate(subscriptionId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Subscription not found: " + subscriptionId));

            if (sub.getRequestsUsed() > 0) {
                sub.setRequestsUsed(sub.getRequestsUsed() - 1);
                subscriptionRepository.save(sub);
            }
            return sub;
        } catch (org.springframework.dao.PessimisticLockingFailureException ex) {
            throw new BadRequestException("The subscription is currently being updated by another request. Please try again.", ex);
        }
    }


    private ServicePackage findPackageInTenant(Long id) {
        return packageRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service package not found: " + id));
    }

    private PackageSubscription findSubscriptionInTenant(Long id) {
        PackageSubscription sub = subscriptionRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Subscription not found: " + id));
        guardSubscriptionAccess(sub);
        return sub;
    }

    // getById/cancel are intentionally open to CLIENT, but a client may only reach their own subscription; staff reach any in their company.
    private void guardSubscriptionAccess(PackageSubscription sub) {
        User user = securityUtil.getCurrentUser();
        if (user == null || user.getRole() == null || !user.getRole().name().equals("CLIENT")) return;

        boolean isOwner = sub.getClient() != null
                && sub.getClient().getUser() != null
                && sub.getClient().getUser().getId().equals(user.getId());

        if (!isOwner) {
            throw new ForbiddenException("You do not have permission to access this subscription");
        }
    }

    private Client resolveClient(Long requestedClientId, Long companyId) {
        User currentUser = securityUtil.getCurrentUser();
        boolean isClient = currentUser.getRole().name().equals("CLIENT");

        if (isClient) {
            // Scoped to companyId, exactly like the on-behalf-of branch below: the resolved client is saved on a
            // PackageSubscription stamped with this company and then billed, so a foreign client record would be
            // subscribed inside this tenant.
            return clientRepository.findByUserIdAndCompanyId(currentUser.getId(), companyId)
                .orElseThrow(() -> new BadRequestException("Client profile not found"));
        }

        if (requestedClientId == null) {
            throw new BadRequestException(
                "clientId is required when subscribing on behalf of a client");
        }
        return clientRepository.findByIdAndCompanyId(requestedClientId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException(
                "Client not found: " + requestedClientId));
    }


    private List<CompanyService> resolveServices(List<Long> ids, Long companyId) {
        List<CompanyService> result = new ArrayList<>();
        for (Long serviceId : ids) {
            result.add(
                companyServiceRepository.findByIdAndCompanyId(serviceId, companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Service not found or does not belong to your company: " + serviceId))
            );
        }
        return result;
    }

    // ONE_TIME returns null: the subscription never expires automatically.
    private LocalDate calculateEndDate(LocalDate start, com.zuhoocms.enums.BillingCycle cycle) {
        return cycle.addTo(start);
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }
}
