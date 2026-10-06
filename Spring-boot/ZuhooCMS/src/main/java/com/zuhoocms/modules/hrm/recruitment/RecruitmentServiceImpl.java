package com.zuhoocms.modules.hrm.recruitment;

import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.enums.JobPostingStatus;
import com.zuhoocms.modules.hrm.employee.CreateEmployeeRequest;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeResponse;
import com.zuhoocms.modules.hrm.employee.EmployeeService;
import com.zuhoocms.modules.hrm.recruitment.ats.CvScoringService;
import com.zuhoocms.modules.hrm.recruitment.candidate.Candidate;
import com.zuhoocms.modules.hrm.recruitment.candidate.CandidateService;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.EvaluateCandidateRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.HireApplicationRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationResponse;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class RecruitmentServiceImpl implements RecruitmentService {

    private final JobApplicationRepository applicationRepository;
    private final com.zuhoocms.modules.hrm.recruitment.offer.JobOfferRepository jobOfferRepository;
    private final com.zuhoocms.modules.hrm.recruitment.jobpost.JobPostingRepository jobPostingRepository;
    private final CandidateService         candidateService;
    private final CvScoringService         cvScoringService;
    private final EmployeeRepository employeeRepository;
    private final EmployeeService           employeeService;
    private final SecurityUtil             securityUtil;
    private final AuthorizationService     authorizationService;

    @Override
    @Transactional
    public JobApplicationResponse apply(Long jobPostingId, JobApplicationRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_CREATE);
        Long companyId = requireCompanyId();
        JobPosting posting = jobPostingRepository.findByIdAndCompanyId(jobPostingId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Job posting not found: " + jobPostingId));

        // Also block a past-deadline posting on the staff entry point; only PublicCareersController.requireOpenPosting() checked it.
        if (posting.getStatus() != JobPostingStatus.OPEN
                || (posting.getDeadline() != null && posting.getDeadline().isBefore(java.time.LocalDate.now()))) {
            throw new BadRequestException("This position is no longer accepting applications");
        }

        ApplicationSource source = request.getSource() != null ? request.getSource() : ApplicationSource.DIRECT;
        Candidate candidate = candidateService.findOrCreate(companyId, request.getApplicantName(),
            request.getApplicantEmail(), request.getApplicantPhone(), source,
            com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getResumeUrl()), request.getLinkedInUrl(), request.getPortfolioUrl());

        // Set once, on first referral: findOrCreate() may return a candidate from an earlier unrelated application whose original attribution must not be overwritten.
        if (request.getReferredByEmployeeId() != null && candidate.getReferredByEmployee() == null) {
            employeeRepository.findByIdAndCompanyId(request.getReferredByEmployeeId(), companyId)
                .ifPresent(candidate::setReferredByEmployee);
        }

        // OFFER_REJECTED included alongside REJECTED/WITHDRAWN: a declined offer is as closed as a rejection, as in TalentPoolController's guard.
        if (applicationRepository.existsByJobPostingIdAndCandidateIdAndStatusNotIn(
                jobPostingId, candidate.getId(),
                java.util.List.of(ApplicationStatus.REJECTED, ApplicationStatus.WITHDRAWN, ApplicationStatus.OFFER_REJECTED))) {
            throw new BadRequestException("An application from this candidate already exists for this position");
        }

        JobApplication application = JobApplication.builder()
            .jobPosting(posting)
            .company(companyRef(companyId))
            .candidate(candidate)
            .applicantName(request.getApplicantName())
            .applicantPhone(request.getApplicantPhone())
            .resumeUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getResumeUrl()))
            .linkedInUrl(request.getLinkedInUrl())
            .portfolioUrl(request.getPortfolioUrl())
            .coverLetter(request.getCoverLetter())
            .source(source)
            .status(ApplicationStatus.APPLIED)
            .build();

        applicationRepository.save(application);
        cvScoringService.scheduleAfterCommit(companyId, application.getId());

        return RecruitmentMapper.toJobApplicationResponse(application);
    }

    @Override
    @Transactional(readOnly = true)
    public JobApplicationResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        return RecruitmentMapper.toJobApplicationResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<JobApplicationResponse> listByPosting(Long jobPostingId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        return applicationRepository.findByCompanyIdAndJobPostingId(
                requireCompanyId(), jobPostingId, pageable)
            .map(RecruitmentMapper::toJobApplicationResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<JobApplicationResponse> listAll(ApplicationStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Long companyId = requireCompanyId();
        return (status != null
            ? applicationRepository.findByCompanyIdAndStatus(companyId, status, pageable)
            : applicationRepository.findByCompanyId(companyId, pageable))
            .map(RecruitmentMapper::toJobApplicationResponse);
    }

    private static final java.util.Set<ApplicationStatus> OFFER_SUB_STATUSES = java.util.Set.of(
        ApplicationStatus.OFFER_PENDING, ApplicationStatus.OFFER_SENT,
        ApplicationStatus.OFFER_ACCEPTED, ApplicationStatus.OFFER_REJECTED);

    @Override
    @Transactional
    public JobApplicationResponse updateStatus(Long id, ApplicationStatus status, String notes) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        // HIRED is only reachable through hire(), the only path that creates the Employee record; setting it here left an application displaying as Hired with no employee and no way back, since hire() requires OFFER_ACCEPTED.
        if (status == ApplicationStatus.HIRED) {
            throw new BadRequestException(
                    "Use the Hire action to mark a candidate as hired - it creates their employee record, "
                            + "which setting status alone does not do");
        }
        // The four offer sub-statuses move only through JobOfferController's actions; letting this generic dropdown set them emailed a candidate the offer twice.
        if (OFFER_SUB_STATUSES.contains(status)) {
            throw new BadRequestException(
                    "Offer status changes only happen from the Offers screen - create, send, accept, "
                            + "decline or withdraw the offer there");
        }
        JobApplication application = findInTenant(id);
        // Moving OFF an offer sub-status or HIRED is equally unsafe: the JobOffer record stays put, so a later accept()/decline()/withdraw() on it silently overwrites whatever this call set.
        if (application.getStatus() == ApplicationStatus.HIRED || OFFER_SUB_STATUSES.contains(application.getStatus())) {
            throw new BadRequestException(
                    "This application has an active offer or is already hired - use the Offers screen or "
                            + "the Hire action to change its status, not the generic dropdown");
        }
        Employee reviewer = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        application.setStatus(status);
        if (notes != null) application.setInterviewNotes(notes);
        // Record rejectionReason: it existed on the entity but no code path set it, leaving no record for later compliance questions.
        if (status == ApplicationStatus.REJECTED && notes != null) {
            application.setRejectionReason(notes);
        }
        application.setReviewedBy(reviewer.getUser());

        return RecruitmentMapper.toJobApplicationResponse(application);
    }

    // Education 20% / Experience 25% / Technical Skills 25% / Interview 20% / Communication 10%.
    private static final java.util.Map<String, Double> SCORE_WEIGHTS = java.util.Map.of(
        "education", 0.20, "experience", 0.25, "technicalSkills", 0.25, "interview", 0.20, "communication", 0.10);

    @Override
    @Transactional
    public JobApplicationResponse evaluate(Long id, EvaluateCandidateRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        JobApplication application = findInTenant(id);

        if (request.getScoreEducation() != null) application.setScoreEducation(request.getScoreEducation());
        if (request.getScoreExperience() != null) application.setScoreExperience(request.getScoreExperience());
        if (request.getScoreTechnicalSkills() != null) application.setScoreTechnicalSkills(request.getScoreTechnicalSkills());
        if (request.getScoreInterview() != null) application.setScoreInterview(request.getScoreInterview());
        if (request.getScoreCommunication() != null) application.setScoreCommunication(request.getScoreCommunication());

        // Renormalized over whichever subscores are set, so a partial evaluation isn't silently under-scored against the full weight of unrated criteria.
        java.util.Map<String, Integer> present = new java.util.LinkedHashMap<>();
        if (application.getScoreEducation() != null) present.put("education", application.getScoreEducation());
        if (application.getScoreExperience() != null) present.put("experience", application.getScoreExperience());
        if (application.getScoreTechnicalSkills() != null) present.put("technicalSkills", application.getScoreTechnicalSkills());
        if (application.getScoreInterview() != null) present.put("interview", application.getScoreInterview());
        if (application.getScoreCommunication() != null) present.put("communication", application.getScoreCommunication());

        if (present.isEmpty()) {
            application.setOverallScore(null);
        } else {
            double totalWeight = present.keySet().stream().mapToDouble(SCORE_WEIGHTS::get).sum();
            double weightedSum = present.entrySet().stream()
                .mapToDouble(e -> SCORE_WEIGHTS.get(e.getKey()) * e.getValue()).sum();
            application.setOverallScore(Math.round((weightedSum / totalWeight) * 10) / 10.0);
        }

        return RecruitmentMapper.toJobApplicationResponse(application);
    }

    @Override
    @Transactional
    public EmployeeResponse hire(Long id, HireApplicationRequest request) {
        // EMPLOYEE_CREATE, not APPLICATION_UPDATE: this creates a real Employee record (portal login, payroll eligibility), and the frontend's Hire button is gated the same way.
        authorizationService.checkPermission(PermissionCode.EMPLOYEE_CREATE);
        JobApplication application = findInTenant(id);

        // id() off the FK, not a proxy read: terminating the hired employee soft-deletes the row, and the proxy then throws.
        if (SoftDeletedProxies.id(application.getConvertedEmployee()) != null) {
            throw new BadRequestException("This application has already been converted to an employee");
        }
        if (application.getStatus() != ApplicationStatus.OFFER_ACCEPTED) {
            throw new BadRequestException(
                "Only candidates with status OFFER_ACCEPTED can be hired. Current status: " + application.getStatus());
        }

        // loadable(), not a null check: both proxies are non-null and throw once the row is soft-deleted, and hiring
        // needs the candidate's email to create the login, so there is nothing to fall back to.
        JobPosting posting = SoftDeletedProxies.loadable(application.getJobPosting());
        Candidate candidate = SoftDeletedProxies.loadable(application.getCandidate());
        if (candidate == null) {
            throw new BadRequestException(
                "This application's candidate record has been deleted and the application can no longer be hired");
        }
        String[] name = splitApplicantName(candidate.getName());

        // The accepted offer is the agreed terms: anything the hire form leaves blank defaults from it, so what HR sent is what the employee gets.
        com.zuhoocms.modules.hrm.recruitment.offer.JobOffer acceptedOffer =
            jobOfferRepository.findByJobApplicationIdOrderByCreatedAtDesc(application.getId()).stream()
                .filter(o -> o.getStatus() == com.zuhoocms.modules.hrm.recruitment.offer.JobOffer.Status.ACCEPTED)
                .findFirst().orElse(null);
        if (acceptedOffer != null) {
            if (request.getBasicSalary() == null) request.setBasicSalary(acceptedOffer.getBasicSalary());
            if (request.getHouseRent() == null) request.setHouseRent(acceptedOffer.getHouseRent());
            if (request.getMedicalAllowance() == null) request.setMedicalAllowance(acceptedOffer.getMedicalAllowance());
            if (request.getTransportAllowance() == null) request.setTransportAllowance(acceptedOffer.getTransportAllowance());
            if (request.getHireDate() == null) request.setHireDate(acceptedOffer.getJoiningDate());
        }

        CreateEmployeeRequest createRequest = new CreateEmployeeRequest();
        createRequest.setFirstName(name[0]);
        createRequest.setLastName(name[1]);
        createRequest.setEmail(candidate.getEmail());
        createRequest.setPassword(request.getPassword());
        createRequest.setOfficialEmail(request.getOfficialEmail());
        createRequest.setWorkPhone(candidate.getPhone());
        createRequest.setJobTitle(acceptedOffer != null && acceptedOffer.getOfferedJobTitle() != null
            ? acceptedOffer.getOfferedJobTitle()
            : (posting != null ? posting.getTitle() : null));
        createRequest.setEmploymentType(request.getEmploymentType() != null
            ? request.getEmploymentType()
            : (posting != null ? posting.getEmploymentType() : null));
        createRequest.setDepartmentId(request.getDepartmentId() != null
            ? request.getDepartmentId()
            : (posting != null ? SoftDeletedProxies.id(posting.getDepartment()) : null));
        createRequest.setDesignationId(request.getDesignationId());
        createRequest.setReportingManagerId(request.getReportingManagerId());
        createRequest.setShiftId(request.getShiftId());
        createRequest.setHireDate(request.getHireDate() != null ? request.getHireDate() : LocalDate.now());
        createRequest.setConfirmationDate(request.getConfirmationDate());
        createRequest.setProbationEndDate(request.getProbationEndDate());
        createRequest.setContractEndDate(request.getContractEndDate());
        createRequest.setBasicSalary(request.getBasicSalary());
        createRequest.setHouseRent(request.getHouseRent());
        createRequest.setMedicalAllowance(request.getMedicalAllowance());
        createRequest.setTransportAllowance(request.getTransportAllowance());
        createRequest.setBankName(request.getBankName());
        createRequest.setBankAccountNumber(request.getBankAccountNumber());
        createRequest.setEmergencyContactName(request.getEmergencyContactName());
        createRequest.setEmergencyContactPhone(request.getEmergencyContactPhone());
        createRequest.setEmergencyContactRelation(request.getEmergencyContactRelation());

        // Same onboarding path as a manual hire: portal user, notification defaults and welcome email all happen inside employeeService.create().
        EmployeeResponse employeeResponse = employeeService.create(createRequest);

        Employee employee = employeeRepository.findByIdAndCompanyId(employeeResponse.getId(), requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeResponse.getId()));

        application.setStatus(ApplicationStatus.HIRED);
        application.setConvertedEmployee(employee);
        application.setConvertedAt(LocalDateTime.now());
        employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .ifPresent(reviewer -> application.setReviewedBy(reviewer.getUser()));

        // Close the posting once every vacancy is filled: it stayed OPEN forever, still accepting applications and showing on the careers page.
        if (posting != null && posting.getStatus() == JobPostingStatus.OPEN && posting.getVacancies() != null) {
            long hiredCount = applicationRepository.countByCompanyIdAndJobPostingIdAndStatus(
                requireCompanyId(), posting.getId(), ApplicationStatus.HIRED);
            if (hiredCount >= posting.getVacancies()) {
                posting.setStatus(JobPostingStatus.CLOSED);
            }
        }

        return employeeResponse;
    }

    /** Applicants only supply one free-text name field; Employee onboarding needs first/last separately. */
    private String[] splitApplicantName(String fullName) {
        String trimmed = fullName == null ? "" : fullName.trim();
        int idx = trimmed.indexOf(' ');
        if (idx < 0) {
            return new String[] { trimmed, trimmed };
        }
        String first = trimmed.substring(0, idx).trim();
        String last = trimmed.substring(idx + 1).trim();
        return new String[] { first, last.isEmpty() ? first : last };
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_DELETE);
        findInTenant(id).softDelete();
    }

    private JobApplication findInTenant(Long id) {
        return applicationRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company(); c.setId(companyId); return c;
    }
}
