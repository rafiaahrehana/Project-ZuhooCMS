package com.zuhoocms.modules.hrm.recruitment.talentpool;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;

/** Talent pool: qualified candidates kept warm for future openings. */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/recruitment/talent-pool")
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class TalentPoolController {

    private final TalentPoolRepository poolRepository;
    private final JobApplicationRepository applicationRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<Page<CandidateResponse>> list(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "24") int size) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Long companyId = requireCompanyId();
        Page<TalentPoolCandidate> result = (keyword != null && !keyword.isBlank())
            ? poolRepository.search(companyId, keyword.trim(), PageRequest.of(page, size))
            : poolRepository.findByCompanyIdOrderByCreatedAtDesc(companyId, PageRequest.of(page, size));
        return ResponseEntity.ok(result.map(CandidateResponse::from));
    }

    @PostMapping
    @Transactional
    public ResponseEntity<CandidateResponse> create(@RequestBody CandidateRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Long companyId = requireCompanyId();
        validate(request);
        if (poolRepository.existsByCompanyIdAndEmailIgnoreCase(companyId, request.getEmail().trim())) {
            throw new BadRequestException("A pooled candidate with that email already exists");
        }
        TalentPoolCandidate candidate = new TalentPoolCandidate();
        Company companyRef = new Company();
        companyRef.setId(companyId);
        candidate.setCompany(companyRef);
        apply(candidate, request);
        return ResponseEntity.ok(CandidateResponse.from(poolRepository.save(candidate)));
    }

    /** One-click pooling of a closed application - contact details come across. */
    @PostMapping("/from-application/{applicationId}")
    @Transactional
    public ResponseEntity<CandidateResponse> fromApplication(@PathVariable Long applicationId,
                                                             @RequestBody(required = false) PoolRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Long companyId = requireCompanyId();
        JobApplication application = applicationRepository.findByIdAndCompanyId(applicationId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + applicationId));
        // Only closed applications can be pooled, so an active mid-pipeline candidate isn't tracked in two places at once.
        // OFFER_REJECTED must be named explicitly alongside REJECTED/WITHDRAWN: the offer sub-pipeline split off from the generic REJECTED status, and a candidate who declined an offer is exactly who this is for.
        if (application.getStatus() != com.zuhoocms.enums.ApplicationStatus.REJECTED
                && application.getStatus() != com.zuhoocms.enums.ApplicationStatus.WITHDRAWN
                && application.getStatus() != com.zuhoocms.enums.ApplicationStatus.OFFER_REJECTED) {
            throw new BadRequestException(
                    "Only a rejected, withdrawn, or declined-offer application can be added to the talent pool");
        }
        // loadable(), not a null check: the proxy is non-null and throws once the candidate is soft-deleted, and
        // pooling needs their email to dedupe, so there is nothing to carry across.
        com.zuhoocms.modules.hrm.recruitment.candidate.Candidate person =
                SoftDeletedProxies.loadable(application.getCandidate());
        if (person == null || person.getEmail() == null) {
            throw new BadRequestException(
                    "This application's candidate record has been deleted and cannot be added to the talent pool");
        }
        if (poolRepository.existsByCompanyIdAndEmailIgnoreCase(companyId, person.getEmail())) {
            throw new BadRequestException("This candidate is already in the talent pool");
        }

        Company companyRef = new Company();
        companyRef.setId(companyId);

        TalentPoolCandidate candidate = TalentPoolCandidate.builder()
                .company(companyRef)
                .name(person.getName())
                .email(person.getEmail())
                .phone(person.getPhone())
                .resumeUrl(person.getResumeUrl())
                .linkedInUrl(person.getLinkedInUrl())
                .desiredRole(desiredRole(application))
                .reason(request != null && request.getReason() != null ? request.getReason() : TalentPoolCandidate.Reason.FUTURE_FIT)
                .notes(request != null ? request.getNotes() : null)
                .sourceApplication(application)
                .build();
        return ResponseEntity.ok(CandidateResponse.from(poolRepository.save(candidate)));
    }

    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<CandidateResponse> update(@PathVariable Long id, @RequestBody CandidateRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        TalentPoolCandidate candidate = requireCandidate(id);
        validate(request);
        apply(candidate, request);
        return ResponseEntity.ok(CandidateResponse.from(candidate));
    }

    @DeleteMapping("/{id}")
    @Transactional
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        // Soft delete, like every other BaseEntity - a hard delete lost the record and its history.
        requireCandidate(id).softDelete();
        return ResponseEntity.noContent().build();
    }

    private void validate(CandidateRequest request) {
        if (request.getName() == null || request.getName().isBlank()) {
            throw new BadRequestException("Name is required");
        }
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            throw new BadRequestException("Email is required");
        }
        if (request.getRating() != null && (request.getRating() < 1 || request.getRating() > 5)) {
            throw new BadRequestException("Rating must be between 1 and 5");
        }
    }

    /**
     * Shared by create and update, and every optional field is null-skipped.
     *
     * Six of these were assigned unconditionally with only {@code reason} guarded, so an update carrying just the
     * name and e-mail it validates silently erased the candidate's phone, resume link, LinkedIn, desired role,
     * skills, rating and notes. That is data loss rather than a no-op, and the response showed the nulls.
     *
     * Null-skipping is also correct on a create: the entity starts empty, so skipping a null leaves exactly the
     * null that assigning it would have written. The resume is guarded on the request value rather than inside
     * requireOwn, because that helper treats a null url as "clear the column" - right for an explicit clear,
     * wrong for an absent key.
     */
    private void apply(TalentPoolCandidate candidate, CandidateRequest request) {
        candidate.setName(request.getName().trim());
        candidate.setEmail(request.getEmail().trim());
        if (request.getPhone() != null) candidate.setPhone(request.getPhone());
        if (request.getResumeUrl() != null) {
            candidate.setResumeUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(
                    request.getResumeUrl(), candidate.getResumeUrl()));
        }
        if (request.getLinkedInUrl() != null) candidate.setLinkedInUrl(request.getLinkedInUrl());
        if (request.getDesiredRole() != null) candidate.setDesiredRole(request.getDesiredRole());
        if (request.getSkills() != null) candidate.setSkills(request.getSkills());
        if (request.getRating() != null) candidate.setRating(request.getRating());
        if (request.getReason() != null) candidate.setReason(request.getReason());
        if (request.getNotes() != null) candidate.setNotes(request.getNotes());
    }

    /** The application's posting title, via loadable() so a soft-deleted posting reads as "no title" rather than throwing. */
    private static String desiredRole(JobApplication application) {
        var posting = SoftDeletedProxies.loadable(application.getJobPosting());
        return posting != null ? posting.getTitle() : null;
    }

    private TalentPoolCandidate requireCandidate(Long id) {
        return poolRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Candidate not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    @Getter @Setter
    public static class CandidateRequest {
        private String name;
        private String email;
        private String phone;
        private String resumeUrl;
        private String linkedInUrl;
        private String desiredRole;
        private String skills;
        private Integer rating;
        private TalentPoolCandidate.Reason reason;
        private String notes;
    }

    @Getter @Setter
    public static class PoolRequest {
        private TalentPoolCandidate.Reason reason;
        private String notes;
    }

    @Getter @Setter
    public static class CandidateResponse {
        private Long id;
        private String name;
        private String email;
        private String phone;
        private String resumeUrl;
        private String linkedInUrl;
        private String desiredRole;
        private String skills;
        private Integer rating;
        private TalentPoolCandidate.Reason reason;
        private String notes;
        private Long sourceApplicationId;
        private String sourceJobTitle;
        private LocalDateTime createdAt;

        static CandidateResponse from(TalentPoolCandidate c) {
            CandidateResponse r = new CandidateResponse();
            r.id = c.getId();
            r.name = c.getName();
            r.email = c.getEmail();
            r.phone = c.getPhone();
            r.resumeUrl = c.getResumeUrl();
            r.linkedInUrl = c.getLinkedInUrl();
            r.desiredRole = c.getDesiredRole();
            r.skills = c.getSkills();
            r.rating = c.getRating();
            r.reason = c.getReason();
            r.notes = c.getNotes();
            // Through SoftDeletedProxies: the source application and its posting are lazy proxies over soft-deletable
            // rows, and either one throws EntityNotFoundException when read, which 500'd the whole pool list.
            r.sourceApplicationId = SoftDeletedProxies.id(c.getSourceApplication());
            var sourceApplication = SoftDeletedProxies.loadable(c.getSourceApplication());
            r.sourceJobTitle = sourceApplication != null ? desiredRole(sourceApplication) : null;
            r.createdAt = c.getCreatedAt();
            return r;
        }
    }
}
