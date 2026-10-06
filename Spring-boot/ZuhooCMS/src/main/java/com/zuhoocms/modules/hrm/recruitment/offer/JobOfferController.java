package com.zuhoocms.modules.hrm.recruitment.offer;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Offer lifecycle: DRAFT -> SENT -> ACCEPTED / DECLINED (or WITHDRAWN); sending moves the application to OFFERED and the accepted offer's salary breakdown is what onboarding pre-fills from.
 * A SENT offer past its expiry reports expired=true as a derived fact, not a stored status, so nothing has to run at midnight.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/recruitment/offers")
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class JobOfferController {

    private final JobOfferRepository offerRepository;
    private final JobApplicationRepository applicationRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final CompanyRepository companyRepository;
    private final EmailService emailService;
    private final EmailBranding emailBranding;

    private static final java.util.Set<ApplicationStatus> OFFERABLE_STATUSES = java.util.Set.of(
            ApplicationStatus.INTERVIEWED, ApplicationStatus.SELECTED, ApplicationStatus.OFFER_REJECTED);

    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<Page<OfferResponse>> list(
            @RequestParam(required = false) JobOffer.Status status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Long companyId = requireCompanyId();
        Page<JobOffer> result = status != null
            ? offerRepository.findByCompanyIdAndStatusOrderByCreatedAtDesc(companyId, status, PageRequest.of(page, size))
            : offerRepository.findByCompanyIdOrderByCreatedAtDesc(companyId, PageRequest.of(page, size));
        return ResponseEntity.ok(result.map(OfferResponse::from));
    }

    @GetMapping("/application/{applicationId}")
    @Transactional(readOnly = true)
    public ResponseEntity<List<OfferResponse>> forApplication(@PathVariable Long applicationId) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        requireApplication(applicationId);
        return ResponseEntity.ok(offerRepository.findByJobApplicationIdOrderByCreatedAtDesc(applicationId)
                .stream().map(OfferResponse::from).toList());
    }

    // Create and edit are DRAFT-only.
    @PostMapping
    @Transactional
    public ResponseEntity<OfferResponse> create(@RequestBody OfferRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Long companyId = requireCompanyId();
        if (request.getJobApplicationId() == null) {
            throw new BadRequestException("Pick an application");
        }
        // Row lock on the application: the one-live-offer check below is read-then-insert, so two concurrent creates could both pass it.
        JobApplication application = applicationRepository
                .findByIdAndCompanyIdForUpdate(request.getJobApplicationId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + request.getJobApplicationId()));
        // An offer follows a hiring decision, so a brand-new APPLIED application is not eligible; OFFER_REJECTED stays eligible so a declined candidate can get a revised offer.
        if (!OFFERABLE_STATUSES.contains(application.getStatus())) {
            throw new BadRequestException("An offer can only be created for an interviewed or selected candidate "
                    + "(current status: " + application.getStatus() + ")");
        }
        // One live offer per application: a second offer while one is pending/accepted is how companies double-commit by accident.
        if (offerRepository.existsByJobApplicationIdAndStatusIn(application.getId(),
                List.of(JobOffer.Status.DRAFT, JobOffer.Status.SENT, JobOffer.Status.ACCEPTED))) {
            throw new BadRequestException("This application already has an active offer - withdraw it first");
        }
        if (request.getOfferedJobTitle() == null || request.getOfferedJobTitle().isBlank()) {
            throw new BadRequestException("Offered job title is required");
        }
        // An offer with no expiry never forces a candidate decision: it sits SENT indefinitely.
        if (request.getExpiryDate() == null) {
            throw new BadRequestException("Expiry date is required");
        }
        if (request.getGrossSalary() == null) {
            throw new BadRequestException("Gross salary is required");
        }
        rejectNegative(request.getGrossSalary(), request.getBasicSalary(), request.getHouseRent(),
                request.getMedicalAllowance(), request.getTransportAllowance());

        Company companyRef = new Company();
        companyRef.setId(companyId);

        JobOffer offer = JobOffer.builder()
                .company(companyRef)
                .jobApplication(application)
                .offeredJobTitle(request.getOfferedJobTitle().trim())
                .joiningDate(request.getJoiningDate())
                .expiryDate(request.getExpiryDate())
                .grossSalary(request.getGrossSalary())
                .basicSalary(request.getBasicSalary())
                .houseRent(request.getHouseRent())
                .medicalAllowance(request.getMedicalAllowance())
                .transportAllowance(request.getTransportAllowance())
                .notes(request.getNotes())
                .build();
        offerRepository.save(offer);
        application.setStatus(ApplicationStatus.OFFER_PENDING);
        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<OfferResponse> update(@PathVariable Long id, @RequestBody OfferRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.DRAFT) {
            throw new BadRequestException("Only a draft offer can be edited - the sent terms are the record");
        }
        // Partial update: an omitted field keeps its value, where assigning straight from the request nulled expiryDate/grossSalary, the two fields create() insists on.
        if (request.getOfferedJobTitle() != null) {
            if (request.getOfferedJobTitle().isBlank()) throw new BadRequestException("Offered job title is required");
            offer.setOfferedJobTitle(request.getOfferedJobTitle().trim());
        }
        rejectNegative(request.getGrossSalary(), request.getBasicSalary(), request.getHouseRent(),
                request.getMedicalAllowance(), request.getTransportAllowance());
        if (request.getJoiningDate() != null)        offer.setJoiningDate(request.getJoiningDate());
        if (request.getExpiryDate() != null)         offer.setExpiryDate(request.getExpiryDate());
        if (request.getGrossSalary() != null)        offer.setGrossSalary(request.getGrossSalary());
        if (request.getBasicSalary() != null)        offer.setBasicSalary(request.getBasicSalary());
        if (request.getHouseRent() != null)          offer.setHouseRent(request.getHouseRent());
        if (request.getMedicalAllowance() != null)   offer.setMedicalAllowance(request.getMedicalAllowance());
        if (request.getTransportAllowance() != null) offer.setTransportAllowance(request.getTransportAllowance());
        if (request.getNotes() != null)              offer.setNotes(request.getNotes());
        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    @DeleteMapping("/{id}")
    @Transactional
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.DRAFT) {
            throw new BadRequestException("Only a draft offer can be deleted - withdraw a sent one instead");
        }
        // Otherwise the application shows OFFER_PENDING with zero offers behind it; same "eligible for a fresh offer" landing spot withdraw() uses.
        JobApplication application = applicationOf(offer);
        if (application.getStatus() == ApplicationStatus.OFFER_PENDING) {
            application.setStatus(ApplicationStatus.SELECTED);
        }
        // Soft delete, like every other BaseEntity.
        offer.softDelete();
        return ResponseEntity.noContent().build();
    }

    @PatchMapping("/{id}/send")
    @Transactional
    public ResponseEntity<OfferResponse> send(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.DRAFT) {
            throw new BadRequestException("Only a draft offer can be sent");
        }
        offer.setStatus(JobOffer.Status.SENT);
        offer.setSentAt(LocalDateTime.now());
        JobApplication application = applicationOf(offer);
        application.setStatus(ApplicationStatus.OFFER_SENT);

        // The only place an offer email goes out: RecruitmentServiceImpl.updateStatus() accepts no offer sub-status, so exactly one path can send it.
        try {
            Company fullCompany = companyRepository.findById(requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
            EmailBranding.Data branding = emailBranding.from(fullCompany);
            // loadable(), not a null check: the candidate proxy is non-null and throws once the candidate is soft-deleted, and there is then no address to write to.
            var candidate = SoftDeletedProxies.loadable(application.getCandidate());
            if (candidate == null || candidate.getEmail() == null) {
                log.warn("Offer letter email skipped - no candidate address on application {}", application.getId());
            } else {
                emailService.sendOfferLetterEmail(candidate.getEmail(), candidate.getName(), branding);
            }
        } catch (Exception ex) {
            log.warn("Offer letter email failed (offer still sent): {}", ex.getMessage());
        }

        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    @PatchMapping("/{id}/accept")
    @Transactional
    public ResponseEntity<OfferResponse> accept(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.SENT) {
            throw new BadRequestException("Only a sent offer can be accepted");
        }
        // The expiry date is the deadline the candidate was given: an expired offer can be declined or re-issued, but not accepted.
        if (offer.getExpiryDate() != null && offer.getExpiryDate().isBefore(LocalDate.now())) {
            throw new BadRequestException("This offer expired on " + offer.getExpiryDate()
                    + " and can no longer be accepted - withdraw it and send a new one");
        }
        requireApplicationStatus(offer, ApplicationStatus.OFFER_SENT);
        offer.setStatus(JobOffer.Status.ACCEPTED);
        offer.setDecidedAt(LocalDateTime.now());
        applicationOf(offer).setStatus(ApplicationStatus.OFFER_ACCEPTED);
        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    @PatchMapping("/{id}/decline")
    @Transactional
    public ResponseEntity<OfferResponse> decline(@PathVariable Long id, @RequestBody(required = false) DeclineRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.SENT) {
            throw new BadRequestException("Only a sent offer can be declined");
        }
        requireApplicationStatus(offer, ApplicationStatus.OFFER_SENT);
        offer.setStatus(JobOffer.Status.DECLINED);
        offer.setDecidedAt(LocalDateTime.now());
        offer.setDeclineReason(request != null ? request.getReason() : null);
        // Declining uses the dedicated OFFER_REJECTED status rather than overloading the generic REJECTED state.
        applicationOf(offer).setStatus(ApplicationStatus.OFFER_REJECTED);
        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    @PatchMapping("/{id}/withdraw")
    @Transactional
    public ResponseEntity<OfferResponse> withdraw(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobOffer offer = requireOffer(id);
        if (offer.getStatus() != JobOffer.Status.SENT && offer.getStatus() != JobOffer.Status.DRAFT) {
            throw new BadRequestException("Only a draft or sent offer can be withdrawn");
        }
        requireApplicationStatus(offer, offer.getStatus() == JobOffer.Status.SENT
                ? ApplicationStatus.OFFER_SENT : ApplicationStatus.OFFER_PENDING);
        offer.setStatus(JobOffer.Status.WITHDRAWN);
        offer.setDecidedAt(LocalDateTime.now());
        // Withdrawing isn't the candidate's fault, so they stay eligible for a fresh offer rather than stuck on a dead-end sub-status.
        applicationOf(offer).setStatus(ApplicationStatus.SELECTED);
        return ResponseEntity.ok(OfferResponse.from(offer));
    }

    // Defense-in-depth alongside RecruitmentServiceImpl.updateStatus()'s guard: fail loudly if the application's status drifts from what this offer's status implies, rather than silently overwriting it.
    private void requireApplicationStatus(JobOffer offer, ApplicationStatus expected) {
        ApplicationStatus actual = applicationOf(offer).getStatus();
        if (actual != expected) {
            throw new BadRequestException(
                    "This application's status (" + actual + ") no longer matches this offer - refresh and check its current state");
        }
    }

    private void rejectNegative(BigDecimal... amounts) {
        for (BigDecimal amount : amounts) {
            if (amount != null && amount.signum() < 0) {
                throw new BadRequestException("Salary amounts cannot be negative");
            }
        }
    }

    private JobOffer requireOffer(Long id) {
        return offerRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Offer not found: " + id));
    }

    private JobApplication requireApplication(Long id) {
        return applicationRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + id));
    }

    /**
     * The offer's application, via loadable() rather than a null check: the lazy proxy is non-null and throws
     * EntityNotFoundException once the application is soft-deleted (BaseEntity's {@code @SQLRestriction}), which
     * 500'd every lifecycle transition on an orphaned offer instead of saying what was wrong.
     */
    private JobApplication applicationOf(JobOffer offer) {
        JobApplication application = SoftDeletedProxies.loadable(offer.getJobApplication());
        if (application == null) {
            throw new BadRequestException("The application behind this offer has been deleted");
        }
        return application;
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    @Getter @Setter
    public static class OfferRequest {
        private Long jobApplicationId;
        private String offeredJobTitle;
        private LocalDate joiningDate;
        private LocalDate expiryDate;
        private BigDecimal grossSalary;
        private BigDecimal basicSalary;
        private BigDecimal houseRent;
        private BigDecimal medicalAllowance;
        private BigDecimal transportAllowance;
        private String notes;
    }

    @Getter @Setter
    public static class DeclineRequest {
        private String reason;
    }

    @Getter @Setter
    public static class OfferResponse {
        private Long id;
        private Long jobApplicationId;
        private String applicantName;
        private String applicantEmail;
        private String jobPostingTitle;
        private String applicationStatus;
        private String offeredJobTitle;
        private LocalDate joiningDate;
        private LocalDate expiryDate;
        private BigDecimal grossSalary;
        private BigDecimal basicSalary;
        private BigDecimal houseRent;
        private BigDecimal medicalAllowance;
        private BigDecimal transportAllowance;
        private JobOffer.Status status;
        private boolean expired;
        private LocalDateTime sentAt;
        private LocalDateTime decidedAt;
        private String declineReason;
        private String notes;
        private LocalDateTime createdAt;

        /*
         * Associations go through SoftDeletedProxies, not != null checks: a lazy proxy to a soft-deleted row is
         * non-null and throws EntityNotFoundException as soon as it is read (BaseEntity's @SQLRestriction).
         * Deleting a candidate leaves their offers live, which 500'd this whole list; applicantName falls back to
         * the value denormalised on the application.
         */
        static OfferResponse from(JobOffer o) {
            JobApplication a = SoftDeletedProxies.loadable(o.getJobApplication());
            var candidate = a == null ? null : SoftDeletedProxies.loadable(a.getCandidate());
            var posting = a == null ? null : SoftDeletedProxies.loadable(a.getJobPosting());

            OfferResponse r = new OfferResponse();
            r.id = o.getId();
            r.jobApplicationId = SoftDeletedProxies.id(o.getJobApplication());
            r.applicantName = candidate != null && candidate.getName() != null
                    ? candidate.getName() : a != null ? a.getApplicantName() : null;
            r.applicantEmail = candidate != null ? candidate.getEmail() : null;
            r.jobPostingTitle = posting != null ? posting.getTitle() : null;
            r.applicationStatus = a != null && a.getStatus() != null ? a.getStatus().name() : null;
            r.offeredJobTitle = o.getOfferedJobTitle();
            r.joiningDate = o.getJoiningDate();
            r.expiryDate = o.getExpiryDate();
            r.grossSalary = o.getGrossSalary();
            r.basicSalary = o.getBasicSalary();
            r.houseRent = o.getHouseRent();
            r.medicalAllowance = o.getMedicalAllowance();
            r.transportAllowance = o.getTransportAllowance();
            r.status = o.getStatus();
            r.expired = o.getStatus() == JobOffer.Status.SENT
                    && o.getExpiryDate() != null && o.getExpiryDate().isBefore(LocalDate.now());
            r.sentAt = o.getSentAt();
            r.decidedAt = o.getDecidedAt();
            r.declineReason = o.getDeclineReason();
            r.notes = o.getNotes();
            r.createdAt = o.getCreatedAt();
            return r;
        }
    }
}
