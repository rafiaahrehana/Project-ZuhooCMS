
package com.zuhoocms.modules.crm.client;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.ClientStatus;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.notification.NotificationPreferenceService;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.contact.ClientContact;
import com.zuhoocms.modules.crm.contact.ClientContactRepository;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.security.JwtService;
import lombok.extern.slf4j.Slf4j;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class ClientServiceImpl implements ClientService {

    private final ClientRepository clientRepository;
    private final UserRepository userRepository;
    private final EmployeeRepository employeeRepository;
    private final PasswordEncoder passwordEncoder;
    private final NotificationPreferenceService notificationPreferenceService;
    private final SecurityUtil securityUtil;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final CompanyRepository companyRepository;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.crm.tag.TagRepository tagRepository;
    private final com.zuhoocms.modules.crm.duplicate.DuplicateDetectionService duplicateDetectionService;
    // Portal invites: the contact holds the email, JwtService mints the one-time set-password token.
    private final ClientContactRepository clientContactRepository;
    private final JwtService jwtService;
    private final com.zuhoocms.modules.crm.opportunity.OpportunityRepository opportunityRepository;

    /** Same window as AuthServiceImpl's own verification codes. */
    private static final int EMAIL_VERIFY_CODE_MINUTES = 15;

    @Override
    @Transactional
    public ClientResponse create(CreateClientRequest request) {
        authorizationService.checkPermission(PermissionCode.CLIENT_CREATE);
        Long companyId = requireCompanyId();

        // Checked before saving, so the new row cannot match itself.
        com.zuhoocms.modules.crm.duplicate.DuplicateMatch possibleDuplicate = duplicateDetectionService
                .findPossibleDuplicateClient(request.getClientCompanyName(), request.getEmail(), request.getPhone())
                .orElse(null);

        boolean provisionLogin = Boolean.TRUE.equals(request.getProvisionPortalLogin());
        User user = null;

        if (provisionLogin) {
            if (request.getFirstName() == null || request.getFirstName().isBlank()
                    || request.getLastName() == null || request.getLastName().isBlank()
                    || request.getEmail() == null || request.getEmail().isBlank()
                    || request.getPassword() == null || request.getPassword().isBlank()) {
                throw new BadRequestException(
                        "First name, last name, email and password are required to provision a portal login");
            }
            String normalizedEmail = request.getEmail().toLowerCase().trim();
            if (userRepository.existsByEmail(normalizedEmail)) {
                throw new BadRequestException("An account with this email already exists");
            }

            user = User.builder()
                    .firstName(request.getFirstName())
                    .lastName(request.getLastName())
                    .email(normalizedEmail)
                    .password(passwordEncoder.encode(request.getPassword()))
                    .phone(request.getPhone())
                    .role(Role.CLIENT)
                    .active(true)
                    .emailVerified(true)
                    .build();
            userRepository.save(user);
        }

        Client client = Client.builder()
                .user(user)
                .company(companyRef(companyId))
                .clientCompanyName(request.getClientCompanyName())
                .industry(request.getIndustry())
                .website(request.getWebsite())
                .taxId(request.getTaxId())
                .billingAddress(request.getBillingAddress())
                .shippingAddress(request.getShippingAddress())
                .tags(request.getTags())
                .employeeCount(request.getEmployeeCount())
                .annualRevenue(request.getAnnualRevenue())
                .status(ClientStatus.ACTIVE)
                .build();

        if (request.getAccountManagerId() != null) {
            client.setAccountManager(findAccountManager(request.getAccountManagerId(), companyId));
        }

        if (request.getTagIds() != null && !request.getTagIds().isEmpty()) {
            client.setTagEntities(com.zuhoocms.modules.crm.support.TagResolver.resolve(
                    tagRepository, request.getTagIds(), companyId));
        }

        clientRepository.save(client);

        if (user != null) {
            notificationPreferenceService.createDefaultsForUser(user.getId());
            try {
                Company fullCompany = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendClientWelcomeEmail(user.getEmail(), user.getFirstName(), branding);
            } catch (Exception ex) {
                log.warn("Welcome email failed for client {}: {}", user.getEmail(), ex.getMessage());
            }
        }

        ClientResponse response = ClientMapper.toResponse(client);
        response.setPossibleDuplicate(possibleDuplicate);
        return response;
    }

    /**
     * Unauthenticated client self-registration, reachable by anyone who can guess a numeric companyId.
     *
     *  - The response is identical whether the address was free or taken; throwing "An account with this email already exists" was an enumeration oracle.
     *  - The account is created unverified and sent the verification email (see AuthServiceImpl.register): emailVerified(true) minted a live CLIENT login into any tenant's portal.
     *  - No welcome email, which belongs after verification.
     *  - The response body carries no id or userId; the Angular caller reads only the status code (see client-register.ts).
     */
    @Override
    @Transactional
    public ClientResponse registerPublic(PublicClientRegisterRequest request) {
        Company company = companyRepository.findById(request.getCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Company not found: " + request.getCompanyId()));
        if (company.getStatus() != CompanyStatus.ACTIVE && company.getStatus() != CompanyStatus.TRIAL) {
            throw new BadRequestException("This company is not currently accepting client registrations");
        }

        String normalizedEmail = request.getEmail().toLowerCase().trim();
        if (userRepository.existsByEmail(normalizedEmail)) {
            // Deliberately indistinguishable from success; the real owner already has an account and resumes via sign-in or password reset.
            log.info("Public client registration for an address that already has an account - "
                    + "answering with the generic response");
            return genericRegistrationResponse(request);
        }

        String verificationCode = generateVerificationCode();
        User user = User.builder()
                .firstName(request.getFirstName())
                .lastName(request.getLastName())
                .email(normalizedEmail)
                .password(passwordEncoder.encode(request.getPassword()))
                .phone(request.getPhone())
                .role(Role.CLIENT)
                .active(true)
                .emailVerified(false)
                .emailVerificationCode(verificationCode)
                .emailVerificationCodeExpiresAt(
                        java.time.LocalDateTime.now().plusMinutes(EMAIL_VERIFY_CODE_MINUTES))
                .build();
        userRepository.save(user);

        Client client = Client.builder()
                .user(user)
                .company(companyRef(company.getId()))
                .clientCompanyName(request.getClientCompanyName())
                .industry(request.getIndustry())
                .website(request.getWebsite())
                .status(ClientStatus.ACTIVE)
                .build();
        clientRepository.save(client);
        notificationPreferenceService.createDefaultsForUser(user.getId());

        try {
            emailService.sendVerificationEmail(user.getEmail(), user.getFirstName(), verificationCode);
        } catch (Exception ex) {
            // A dead SMTP connection must not roll the registration back, nor change the response, or the timing/shape difference becomes the enumeration oracle again.
            log.warn("Verification email failed for public client registration: {}", ex.getMessage());
        }

        return genericRegistrationResponse(request);
    }

    /** Identical for a new account and for an address that already had one. */
    private ClientResponse genericRegistrationResponse(PublicClientRegisterRequest request) {
        ClientResponse response = new ClientResponse();
        response.setClientCompanyName(request.getClientCompanyName());
        response.setIndustry(request.getIndustry());
        response.setWebsite(request.getWebsite());
        response.setStatus(ClientStatus.ACTIVE);
        return response;
    }

    /** Matches AuthServiceImpl's six-digit code. */
    private String generateVerificationCode() {
        return String.valueOf(100000 + new java.security.SecureRandom().nextInt(900000));
    }

    /**
     * Checks CLIENT_VIEW, like listAll does.
     *
     * It used to check nothing while every sibling on this class did - create, update, delete and the list - so an
     * employee with no permissions could read any client row by id, including its billing address, tax id, annual
     * revenue and lifetime value. The list it was meant to be reached from was closed to them.
     *
     * The same hole in the same module family had already been found and closed next door, where
     * ClientContactServiceImpl.getById carries the note "Its list siblings check CONTACT_VIEW; unguarded, this
     * single-row read was the way around them." This is that fix, one class late.
     *
     * getMyProfile below is deliberately unchecked and stays so: a client reads their own record.
     */
    @Override
    @Transactional(readOnly = true)
    public ClientResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.CLIENT_VIEW);
        Client client = findInTenant(id);
        return ClientMapper.toResponse(client, primaryContactEmail(client), primaryContactPhone(client));
    }

    @Override
    @Transactional(readOnly = true)
    public ClientResponse getMyProfile() {
        User user = securityUtil.getCurrentUser();
        // Scoped to the active company: the response carries the whole client row (billing/shipping address,
        // taxId, lifetime value), and findByUserId alone could resolve the record from a different tenant.
        Client client = clientRepository.findByUserIdAndCompanyId(user.getId(), requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Client profile not found"));
        return ClientMapper.toResponse(client);
    }

    @Override
    @Transactional
    public ClientResponse updateMyProfile(UpdateMyClientProfileRequest request) {
        User user = securityUtil.getCurrentUser();
        // Scoped before any setter runs: this used to be able to overwrite another tenant's client row.
        Client client = clientRepository.findByUserIdAndCompanyId(user.getId(), requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Client profile not found"));

        if (request.getClientCompanyName() != null) client.setClientCompanyName(request.getClientCompanyName());
        if (request.getIndustry() != null) client.setIndustry(request.getIndustry());
        if (request.getWebsite() != null) client.setWebsite(request.getWebsite());
        if (request.getBillingAddress() != null) client.setBillingAddress(request.getBillingAddress());
        if (request.getShippingAddress() != null) client.setShippingAddress(request.getShippingAddress());

        clientRepository.save(client);
        return ClientMapper.toResponse(client);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientResponse> listAll(ClientStatus status, Long tagId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.CLIENT_VIEW);
        Long companyId = requireCompanyId();
        Page<Client> page;
        if (tagId != null) {
            page = clientRepository.findByCompanyIdAndTagEntitiesId(companyId, tagId, pageable);
        } else if (status != null) {
            page = clientRepository.findByCompanyIdAndStatus(companyId, status, pageable);
        } else {
            page = clientRepository.findByCompanyId(companyId, pageable);
        }
        return page.map(ClientMapper::toResponse);
    }

    // Deliberately NOT gated by CLIENT_VIEW: it populates the client dropdown for users with only INVOICE_VIEW/PAYMENT_RECEIPT_VIEW/OPPORTUNITY_VIEW.
    @Override
    @Transactional(readOnly = true)
    public List<ClientResponse> listActive() {
        return clientRepository.findByCompanyIdAndStatus(requireCompanyId(), ClientStatus.ACTIVE)
                .stream().map(ClientMapper::toResponse).toList();
    }

    @Override
    @Transactional
    public ClientResponse update(Long id, UpdateClientRequest request) {
        authorizationService.checkPermission(PermissionCode.CLIENT_UPDATE);
        Long companyId = requireCompanyId();
        Client client = findInTenant(id);

        if (request.getClientCompanyName()!= null) client.setClientCompanyName(request.getClientCompanyName());
        if (request.getIndustry()!= null) client.setIndustry(request.getIndustry());
        if (request.getWebsite()!= null) client.setWebsite(request.getWebsite());
        if (request.getTaxId()!= null) client.setTaxId(request.getTaxId());
        if (request.getStatus()!= null) client.setStatus(request.getStatus());
        if (request.getPortalAccessEnabled()!= null) client.setPortalAccessEnabled(request.getPortalAccessEnabled());
        if (request.getBillingAddress() != null) client.setBillingAddress(request.getBillingAddress());
        if (request.getShippingAddress() != null) client.setShippingAddress(request.getShippingAddress());
        if (request.getTags() != null) client.setTags(request.getTags());
        if (request.getEmployeeCount() != null) client.setEmployeeCount(request.getEmployeeCount());
        if (request.getAnnualRevenue() != null) client.setAnnualRevenue(request.getAnnualRevenue());

        if (request.getAccountManagerId() != null) {
            client.setAccountManager(findAccountManager(request.getAccountManagerId(), companyId));
        }

        if (request.getTagIds() != null) {
            client.setTagEntities(com.zuhoocms.modules.crm.support.TagResolver.resolve(
                    tagRepository, request.getTagIds(), companyId));
        }

        clientRepository.save(client);
        return ClientMapper.toResponse(client);
    }

    /** Gives a client a portal login via an emailed set-password link, never a staff-chosen password: the stored one is random and shown to nobody. Re-invitable on purpose, to reissue an expired or lost link. */
    @Override
    @Transactional
    public ClientResponse inviteToPortal(Long id) {
        authorizationService.checkPermission(PermissionCode.CLIENT_UPDATE);
        Client client = findInTenant(id);
        Long companyId = requireCompanyId();

        User user = client.getUser();

        if (user == null) {
            // The primary contact is the only place an email is stored for a client.
            String email = primaryContactEmail(client);
            if (email == null) {
                throw new BadRequestException(
                    "This client has no contact email. Add a contact with an email address first.");
            }

            String normalized = email.trim().toLowerCase();
            user = userRepository.findByEmail(normalized).orElse(null);

            if (user == null) {
                String contactName = primaryContactName(client);
                user = User.builder()
                        .firstName(firstWord(contactName))
                        .lastName(remainingWords(contactName))
                        .email(normalized)
                        .password(passwordEncoder.encode(UUID.randomUUID() + "-" + UUID.randomUUID()))
                        .role(Role.CLIENT)
                        .active(true)
                        // Clicking the emailed link already proves they control the address.
                        .emailVerified(true)
                        .build();
                userRepository.save(user);
            } else if (user.getRole() != Role.CLIENT) {
                throw new BadRequestException(
                    "An account already exists for " + normalized + " with a different role.");
            }

            client.setUser(user);
        }

        client.setPortalAccessEnabled(true);
        clientRepository.save(client);

        // 7 days, not the 15-minute reset window: an invite often sits unopened over a weekend.
        String token = jwtService.generateActionToken(
                user.getEmail(), TokenType.PASSWORD_RESET, 7L * 24 * 60 * 60 * 1000);

        // The login is provisioned even if the email fails (invite again is the recovery), but the caller is told, so "invite sent" never appears when nothing was delivered.
        boolean emailSent = false;
        String emailError = null;

        Company company = companyRepository.findById(companyId).orElse(null);
        if (company == null) {
            emailError = "Company record not found, so no invite could be sent.";
            log.warn("Portal invite for client {} sent no email - company {} not found",
                    client.getId(), companyId);
        } else {
            try {
                emailService.sendClientPortalInviteEmail(
                        user.getEmail(), user.getFirstName(),
                        token, emailBranding.from(company));
                emailSent = true;
            } catch (Exception ex) {
                // sendInternal already logged a FAILED row in email_logs; this only surfaces it to the caller.
                emailError = "The portal login was created, but the invite email could not be delivered.";
                log.warn("Portal invite email failed for client {} ({}): {}",
                        client.getId(), user.getEmail(), ex.getMessage());
            }
        }

        ClientResponse response = ClientMapper.toResponse(client);
        response.setInviteEmailSent(emailSent);
        response.setInviteEmailError(emailError);
        return response;
    }

    private String primaryContactEmail(Client client) {
        return clientContactRepository
                .findFirstByClientIdAndCompanyIdAndPrimaryContactTrueAndDeletedFalseOrderByIdAsc(client.getId(), client.getCompany().getId())
                .map(ClientContact::getEmail)
                .filter(e -> e != null && !e.isBlank())
                .orElse(null);
    }

    private String primaryContactPhone(Client client) {
        return clientContactRepository
                .findFirstByClientIdAndCompanyIdAndPrimaryContactTrueAndDeletedFalseOrderByIdAsc(client.getId(), client.getCompany().getId())
                .map(ClientContact::getPhone)
                .filter(p -> p != null && !p.isBlank())
                .orElse(null);
    }

    private String primaryContactName(Client client) {
        return clientContactRepository
                .findFirstByClientIdAndCompanyIdAndPrimaryContactTrueAndDeletedFalseOrderByIdAsc(client.getId(), client.getCompany().getId())
                .map(ClientContact::getFullName)
                .filter(n -> n != null && !n.isBlank())
                .orElse(client.getClientCompanyName());
    }

    private String firstWord(String full) {
        if (full == null || full.isBlank()) return "Client";
        return full.trim().split("\\s+")[0];
    }

    private String remainingWords(String full) {
        if (full == null || full.isBlank()) return "";
        String[] parts = full.trim().split("\\s+", 2);
        return parts.length > 1 ? parts[1] : "";
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.CLIENT_DELETE);
        Client client = findInTenant(id);

        // Blocked rather than orphaned: soft-deleting hides the client from every lookup while open Opportunities still point at it.
        long openOpportunities = opportunityRepository.countByCompanyIdAndClientIdAndStageNotIn(
                client.getCompany().getId(), client.getId(),
                List.of(com.zuhoocms.modules.crm.opportunity.OpportunityStage.WON,
                        com.zuhoocms.modules.crm.opportunity.OpportunityStage.LOST));
        if (openOpportunities > 0) {
            throw new BadRequestException(
                    "Cannot delete this client: it has " + openOpportunities
                            + " open opportunity/opportunities. Close or reassign them first.");
        }

        client.softDelete();
        clientRepository.save(client);

        // Contacts go too: left live, they kept matching in duplicate detection, whose getClient() proxy for a @SQLRestriction-hidden row caused 500s and a 404 "Client not found" when marking an unrelated deal Won.
        int orphaned = clientContactRepository.softDeleteByClientId(
                client.getId(), client.getCompany().getId(), java.time.LocalDateTime.now());
        if (orphaned > 0) {
            log.info("Soft-deleted {} contact(s) along with client {}", orphaned, client.getId());
        }

        User user = client.getUser();
        if (user != null) {
            user.setActive(false);
            user.softDelete();
            userRepository.save(user);
        }
        
    }

    @Override
    @Transactional(readOnly = true)
    public long getClientCount() {
        return clientRepository.countByCompanyId(requireCompanyId());
    }

    @Override
    @Transactional(readOnly = true)
    public boolean isClient(Long userId) {
        return clientRepository.existsByUserIdAndCompanyId(userId, requireCompanyId());
    }

    /** Only a still-employed employee can be an account manager: company membership alone let clients be handed to leavers, so escalations went nowhere. */
    private Employee findAccountManager(Long employeeId, Long companyId) {
        return employeeRepository.findAssignableByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Account manager not found, or is no longer an active employee: " + employeeId));
    }

    private Client findInTenant(Long id) {
        return clientRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Client not found: " + id));
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