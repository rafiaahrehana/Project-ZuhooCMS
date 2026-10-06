
package com.zuhoocms.modules.company;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.token.TokenRepository;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.modules.website.WebsiteSettingsRepository;
import com.zuhoocms.shared.address.AddressMapper;
import com.zuhoocms.shared.subscription.BillingCycle;
import com.zuhoocms.shared.subscription.SubscriptionHistory;
import com.zuhoocms.shared.subscription.SubscriptionHistoryRepository;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinition;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinitionRepository;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor

@Transactional
public class CompanyServiceImpl implements CompanyService {

    private final CompanyRepository companyRepository;
    private final UserRepository userRepository;
    private final EmployeeRepository employeeRepository;
    private final ClientRepository clientRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final CompanyServiceRepository hubServiceRepository;
    private final SubscriptionHistoryRepository subscriptionHistoryRepository;
    private final SubscriptionPlanDefinitionRepository subscriptionPlanDefinitionRepository;
    private final SecurityUtil securityUtil;
    private final WebsiteSettingsRepository websiteSettingsRepository;
    private final AddressMapper addressMapper;
    private final PasswordEncoder passwordEncoder;
    private final AuthorizationService authorizationService;
    private final AuditService auditService;
    private final com.zuhoocms.shared.notification.NotificationService notificationService;
    private final TokenRepository tokenRepository;
    private final com.zuhoocms.modules.finance.generalledger.GeneralLedgerRepository generalLedgerRepository;
    private final com.zuhoocms.modules.demo.DemoAccount demoAccount;
    private final com.zuhoocms.core.interceptor.UnfilteredReads unfilteredReads;

    @Override
    @Transactional(readOnly = true)
    public CompanyPublicResponse getBySubdomain(String subdomain) {
        Company company = companyRepository.findBySubdomain(subdomain)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found with subdomain: " + subdomain));
        CompanyPublicResponse publicResponse = CompanyMapper.toPublicResponse(company);
        unfilteredReads.run(() -> { applyBranding(publicResponse, company.getId()); return null; });
        return publicResponse;
    }

    @Override
    @Transactional(readOnly = true)
    public java.util.List<CompanyPublicListItem> getPublicList() {
        // Verified tenants only, four fields, one query, capped - not every ACTIVE/TRIAL row with contact details.
        Long demoOwner = demoAccount.demoUserId();
        return unfilteredReads.run(() -> companyRepository.findPublicList(
                List.of(CompanyStatus.ACTIVE, CompanyStatus.TRIAL),
                demoOwner != null ? demoOwner : -1L,
                org.springframework.data.domain.PageRequest.of(0, PUBLIC_LIST_LIMIT)));
    }

    private static final int PUBLIC_LIST_LIMIT = 500;

    @Override
    @Transactional(readOnly = true)
    public java.util.List<com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceResponse> getPublicServices(String subdomain) {
        Company company = companyRepository.findBySubdomain(subdomain)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found with subdomain: " + subdomain));
        // Explicit company id with the tenant filter off, so a logged-in user of another company sees this company's services.
        return unfilteredReads.run(() -> hubServiceRepository.findByCompanyIdAndActiveTrue(company.getId())
                .stream()
                .map(com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceMapper::toResponse)
                .toList());
    }

    private static boolean changes(String requested, String current) {
        return requested != null && !requested.equals(current == null ? "" : current)
                && !(requested.isEmpty() && current == null);
    }

    @Override
    @Transactional(readOnly = true)
    public CompanyResponse getById(Long id) {
        Company company = companyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found with id : " + id));
        CompanyResponse response = CompanyMapper.toResponse(company);
        response.setLocationDetail(addressMapper.toResponse(company.getLocationDetail()));
        applyBranding(response, company.getId());
        if (demoAccount.isDemoCompany(company)) {
            // The demo tenant has no trial window by design; never show it as expired.
            response.setTrialExpired(false);
        }
        return response;
    }

    @Override
    public CompanyResponse update(Long id, UpdateCompanyRequest request) {
        authorizationService.checkAnyPermission(
                PermissionCode.COMPANY_UPDATE, PermissionCode.COMPANY_SETTINGS, PermissionCode.COMPANY_BRANDING);

        Company company = companyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        if (request.getCompanyName() != null) company.setCompanyName(request.getCompanyName());
        if (request.getCompanyPhone() != null) company.setCompanyPhone(request.getCompanyPhone());
        if (request.getWebsite() != null) company.setWebsite(request.getWebsite());
        if (request.getPortalAbout() != null) company.setPortalAbout(request.getPortalAbout());
        if (request.getTaxRegistrationNumber() != null) company.setTaxRegistrationNumber(request.getTaxRegistrationNumber());

        // Bank details and ledger currency need COMPANY_SETTINGS, not COMPANY_BRANDING, or a branding-only user could redirect client payments.
        // Only an actual change is gated, so a form echoing the current values back still works.
        boolean bankChange = changes(request.getBankName(), company.getBankName())
                || changes(request.getBankAccountName(), company.getBankAccountName())
                || changes(request.getBankAccountNumber(), company.getBankAccountNumber())
                || changes(request.getBankBranch(), company.getBankBranch());
        String newCurrency = request.getBaseCurrency() != null && !request.getBaseCurrency().isBlank()
                ? request.getBaseCurrency().trim().toUpperCase(java.util.Locale.ROOT) : null;
        boolean currencyChange = newCurrency != null && !newCurrency.equals(company.getBaseCurrency());
        if (bankChange || currencyChange) {
            authorizationService.checkPermission(PermissionCode.COMPANY_SETTINGS);
        }
        if (request.getBankName() != null) company.setBankName(request.getBankName());
        if (request.getBankAccountName() != null) company.setBankAccountName(request.getBankAccountName());
        if (request.getBankAccountNumber() != null) company.setBankAccountNumber(request.getBankAccountNumber());
        if (request.getBankBranch() != null) company.setBankBranch(request.getBankBranch());
        if (request.getFiscalYearStartMonth() != null) {
            if (request.getFiscalYearStartMonth() < 1 || request.getFiscalYearStartMonth() > 12) {
                throw new BadRequestException("Fiscal year start month must be between 1 and 12");
            }
            company.setFiscalYearStartMonth(request.getFiscalYearStartMonth());
        }
        if (currencyChange) {
            try {
                java.util.Currency.getInstance(newCurrency);
            } catch (IllegalArgumentException ex) {
                throw new BadRequestException("'" + newCurrency + "' is not a valid ISO-4217 currency code");
            }
            // Every posted amount is in the base currency, so switching it would silently re-denominate the whole ledger.
            if (generalLedgerRepository.existsByCompanyId(company.getId())) {
                throw new BadRequestException(
                        "The base currency cannot be changed once the company has ledger transactions");
            }
            company.setBaseCurrency(newCurrency);
        }

        if (request.getLogo() != null || request.getPrimaryColor() != null
                || request.getSecondaryColor() != null || request.getTagline() != null) {
            com.zuhoocms.modules.website.WebsiteSettings settings =
                    websiteSettingsRepository.findByCompanyId(company.getId())
                            .orElseGet(() -> com.zuhoocms.modules.website.WebsiteSettings.builder()
                                    .companyId(company.getId())
                                    .companyName(company.getCompanyName())
                                    .build());
            if (request.getLogo() != null) settings.setLogoUrl(
                    com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getLogo(), settings.getLogoUrl()));
            if (request.getPrimaryColor() != null) settings.setPrimaryColor(request.getPrimaryColor());
            if (request.getSecondaryColor() != null) settings.setSecondaryColor(request.getSecondaryColor());
            if (request.getTagline() != null) settings.setTagline(request.getTagline());
            websiteSettingsRepository.save(settings);
        }

        if (request.getLocationDetail() != null) {
            if (company.getLocationDetail() == null) {
                company.setLocationDetail(addressMapper.toEntity(request.getLocationDetail()));
            } else {
                addressMapper.updateEntityFromRequest(company.getLocationDetail(), request.getLocationDetail());
            }
        }

        Company savedCompany = companyRepository.save(company);
        CompanyResponse response = CompanyMapper.toResponse(savedCompany);
        response.setLocationDetail(addressMapper.toResponse(savedCompany.getLocationDetail()));
        applyBranding(response, savedCompany.getId());
        return response;
    }

    @Override
    public CompanyResponse registerByAdmin(RegisterCompanyRequest request) {
        ReservedSubdomains.requireAllowed(request.getSubdomain());
        if (companyRepository.existsAnyBySubdomain(request.getSubdomain().trim())) {
            throw new BadRequestException("Subdomain already exists.");
        }
        if (userRepository.existsAnyByEmailIgnoreCase(request.getOwnerEmail().trim())) {
            throw new BadRequestException("Email already exists.");
        }

        User owner = new User();
        owner.setFirstName(request.getOwnerFirstName());
        owner.setLastName(request.getOwnerLastName());
        owner.setEmail(request.getOwnerEmail().toLowerCase().trim());
        owner.setPassword(passwordEncoder.encode(request.getOwnerPassword()));
        owner.setRole(Role.COMPANY_OWNER);
        owner.setPhone(request.getCompanyPhone());
        owner.setActive(true);
        // Created by platform staff, not a self sign-up: nothing to verify, and login() refuses unverified owners.
        owner.setEmailVerified(true);
        owner = userRepository.save(owner);

        Company company = new Company();
        company.setCompanyName(request.getCompanyName());
        company.setSubdomain(request.getSubdomain().toLowerCase().trim());
        company.setCompanyPhone(request.getCompanyPhone());
        company.setCompanyEmail(request.getOwnerEmail().toLowerCase().trim());
        company.setOwner(owner);
        company.setStatus(CompanyStatus.ACTIVE);
        company.setSubscriptionPlan("FREE");
        if (request.getLocationDetail() != null) {
            company.setLocationDetail(addressMapper.toEntity(request.getLocationDetail()));
        }

        company = companyRepository.save(company);
        return CompanyMapper.toResponse(company);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<CompanyResponse> listAll(CompanyStatus status, String plan, String keyword, Pageable pageable) {
        return companyRepository
            .findFiltered(status, plan, keyword == null ? null : keyword.trim(), pageable)
            .map(CompanyMapper::toResponse);
    }

    @Override
    public CompanyResponse changePlan(Long id, String planCode, BigDecimal amountPaid, String transactionRef) {
        Company company = companyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
        SubscriptionPlanDefinition planDef = subscriptionPlanDefinitionRepository.findByCode(planCode)
                .orElseThrow(() -> new ResourceNotFoundException("Unknown plan: " + planCode));

        String fromPlan = company.getSubscriptionPlan();
        LocalDate today = LocalDate.now();
        company.setSubscriptionPlan(planDef.getCode());
        // An admin-assigned plan gets a real subscription window from the billing cycle, as the self-service upgrade does.
        company.setSubscriptionStart(today);
        company.setSubscriptionEnd(planDef.getBillingCycle() == BillingCycle.YEARLY
                ? today.plusYears(1) : today.plusMonths(1));
        // findTrialExpiringBetween() excludes any company with this set, so without the reset one reminder would be the last ever.
        company.setTrialReminderSentAt(null);
        Company saved = companyRepository.save(company);

        subscriptionHistoryRepository.save(SubscriptionHistory.builder()
                .company(saved)
                .fromPlan(fromPlan)
                .toPlan(planDef.getCode())
                .subscriptionStart(saved.getSubscriptionStart())
                .subscriptionEnd(saved.getSubscriptionEnd())
                .amountPaid(amountPaid)
                .transactionRef(transactionRef)
                .changedAt(LocalDateTime.now())
                .changedBy(securityUtil.getCurrentUser())
                .build());

        if (saved.getOwner() != null && !planDef.getCode().equals(fromPlan)) {
            notificationService.send(com.zuhoocms.shared.notification.CreateNotificationRequest.of(
                    com.zuhoocms.enums.NotificationType.GENERAL,
                    "Your plan was changed",
                    "Your company's plan was changed from " + fromPlan + " to " + planDef.getCode()
                            + " by a platform administrator.",
                    "/settings/subscription",
                    saved.getOwner().getId(),
                    id));
        }

        return CompanyMapper.toResponse(saved);
    }

    @Override
    public void applyPaidPlanUpgrade(Long companyId, SubscriptionPlanDefinition plan, BigDecimal amountPaid,
                                     String transactionRef, Long changedByUserId) {
        Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        String fromPlan = company.getSubscriptionPlan();
        LocalDate today = LocalDate.now();
        company.setSubscriptionPlan(plan.getCode());
        company.setSubscriptionStart(today);
        company.setSubscriptionEnd(plan.getBillingCycle() == BillingCycle.YEARLY
                ? today.plusYears(1) : today.plusMonths(1));
        // Same reset as changePlan(), or one reminder would exclude the company from every future run.
        company.setTrialReminderSentAt(null);
        company.setActive(true);
        // A paid upgrade reactivates immediately, matching the "reactivate on payment" behaviour SubscriptionScheduler's suspension implies.
        if (company.getStatus() == CompanyStatus.TRIAL || company.getStatus() == CompanyStatus.SUSPENDED
                || company.getStatus() == CompanyStatus.PENDING_VERIFICATION) {
            company.setStatus(CompanyStatus.ACTIVE);
        }
        Company saved = companyRepository.save(company);

        // changedBy comes from initiatedByUserId, not SecurityUtil: this runs from a payment gateway callback with no security context.
        subscriptionHistoryRepository.save(SubscriptionHistory.builder()
                .company(saved)
                .fromPlan(fromPlan)
                .toPlan(plan.getCode())
                .subscriptionStart(saved.getSubscriptionStart())
                .subscriptionEnd(saved.getSubscriptionEnd())
                .amountPaid(amountPaid)
                .transactionRef(transactionRef)
                .changedAt(LocalDateTime.now())
                .changedBy(changedByUserId != null ? userRepository.findById(changedByUserId).orElse(null) : null)
                .build());
    }

    @Override
    public CompanyResponse changeStatus(Long id, CompanyStatus status) {
        Company company = companyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        if (status == CompanyStatus.DEACTIVATED || status == CompanyStatus.SUSPENDED) {
            boolean hasActiveRequests = serviceRequestRepository.existsByCompanyIdAndStatusNotIn(
                id, List.of(ServiceRequestStatus.COMPLETED, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED)
            );
            if (hasActiveRequests) {
                throw new BadRequestException("Cannot change status. There are active service requests.");
            }
        }

        CompanyStatus oldStatus = company.getStatus();
        company.setStatus(status);
        if (status == CompanyStatus.ACTIVE) {
            company.setActive(true);
        } else if (status == CompanyStatus.SUSPENDED || status == CompanyStatus.DEACTIVATED) {
            company.setActive(false);
            // login() blocks new logins, but an existing refresh token would keep minting access tokens past the suspension.
            revokeSessionsForCompany(company);
        }
        CompanyResponse response = CompanyMapper.toResponse(companyRepository.save(company));

        // Suspending/reactivating a whole tenant is high blast radius, so it must leave an audit trail.
        auditService.log(AuditEntityType.COMPANY, id, AuditAction.UPDATE,
                oldStatus != null ? oldStatus.name() : null, status.name(),
                securityUtil.getCurrentUser(), id, null);

        // Tell the owner, or they only discover an admin-driven status change when features start disappearing.
        if (company.getOwner() != null && oldStatus != status) {
            notificationService.send(com.zuhoocms.shared.notification.CreateNotificationRequest.of(
                    com.zuhoocms.enums.NotificationType.GENERAL,
                    "Your company status changed",
                    "Your company's status was changed to " + status + " by a platform administrator.",
                    "/settings/subscription",
                    company.getOwner().getId(),
                    id));
        }

        return response;
    }

    @Override
    public void deactivate(Long id) {
        Company company = companyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        boolean hasActiveRequests = serviceRequestRepository.existsByCompanyIdAndStatusNotIn(
            id, List.of(ServiceRequestStatus.COMPLETED, ServiceRequestStatus.REJECTED, ServiceRequestStatus.CANCELLED)
        );
        if (hasActiveRequests) {
            throw new BadRequestException("Cannot deactivate company. There are active service requests.");
        }

        if (employeeRepository.existsByCompanyId(id)) {
            throw new BadRequestException("Cannot delete company with existing employees.");
        }

        if (clientRepository.existsByCompanyId(id)) {
            throw new BadRequestException("Cannot delete company with existing clients.");
        }

        CompanyStatus oldStatus = company.getStatus();
        company.setActive(false);
        company.softDelete();
        companyRepository.save(company);

        if (company.getOwner() != null) {
            company.getOwner().softDelete();
            company.getOwner().setActive(false);
            userRepository.save(company.getOwner());
        }

        auditService.log(AuditEntityType.COMPANY, id, AuditAction.UPDATE,
                oldStatus != null ? oldStatus.name() : null, "DEACTIVATED",
                securityUtil.getCurrentUser(), id, null);
    }

    // Revokes every REFRESH token for the tenant's owner, employees and clients so none can refresh past a suspension.
    private void revokeSessionsForCompany(Company company) {
        java.util.List<Long> userIds = new java.util.ArrayList<>();
        if (company.getOwner() != null) {
            userIds.add(company.getOwner().getId());
        }
        userIds.addAll(employeeRepository.findUserIdsByCompanyId(company.getId()));
        userIds.addAll(clientRepository.findUserIdsByCompanyId(company.getId()));
        userIds.removeIf(java.util.Objects::isNull);
        if (!userIds.isEmpty()) {
            tokenRepository.revokeAllByUserIdInAndType(userIds, TokenType.REFRESH);
        }
    }

    // WebsiteSettings is authoritative over the legacy Company branding columns when a settings row exists.
    private void applyBranding(CompanyResponse response, Long companyId) {
        websiteSettingsRepository.findByCompanyId(companyId).ifPresent(settings -> {
            if (settings.getLogoUrl() != null) response.setLogo(settings.getLogoUrl());
            if (settings.getPrimaryColor() != null) response.setPrimaryColor(settings.getPrimaryColor());
            if (settings.getSecondaryColor() != null) response.setSecondaryColor(settings.getSecondaryColor());
            if (settings.getTagline() != null) response.setTagline(settings.getTagline());
        });
    }

    private void applyBranding(CompanyPublicResponse response, Long companyId) {
        websiteSettingsRepository.findByCompanyId(companyId).ifPresent(settings -> {
            if (settings.getLogoUrl() != null) response.setLogo(settings.getLogoUrl());
            if (settings.getPrimaryColor() != null) response.setPrimaryColor(settings.getPrimaryColor());
            if (settings.getSecondaryColor() != null) response.setSecondaryColor(settings.getSecondaryColor());
            if (settings.getTagline() != null) response.setTagline(settings.getTagline());
        });
    }
}
