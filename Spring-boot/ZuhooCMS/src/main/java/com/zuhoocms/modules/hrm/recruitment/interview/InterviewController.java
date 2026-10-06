package com.zuhoocms.modules.hrm.recruitment.interview;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeUserResolver;
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

import java.time.LocalDateTime;
import java.util.List;

/**
 * Interview scheduling and feedback for job applications; scheduling the first round moves an early-stage application to INTERVIEW_SCHEDULED, completing the last outstanding round moves it to INTERVIEWED.
 * Uses the APPLICATION_* permission codes, since interviews are part of working an application.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/recruitment/interviews")
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class InterviewController {

    private final InterviewRepository interviewRepository;
    private final JobApplicationRepository applicationRepository;
    private final EmployeeRepository employeeRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final CompanyRepository companyRepository;
    private final EmailService emailService;
    private final EmailBranding emailBranding;

    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<Page<InterviewResponse>> list(
            @RequestParam(required = false) Interview.Status status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Long companyId = requireCompanyId();
        Page<Interview> result = status != null
            ? interviewRepository.findByCompanyIdAndStatusOrderByScheduledAtAsc(companyId, status, PageRequest.of(page, size))
            : interviewRepository.findByCompanyIdOrderByScheduledAtDesc(companyId, PageRequest.of(page, size));
        return ResponseEntity.ok(result.map(InterviewResponse::from));
    }

    @GetMapping("/application/{applicationId}")
    @Transactional(readOnly = true)
    public ResponseEntity<List<InterviewResponse>> forApplication(@PathVariable Long applicationId) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        requireApplication(applicationId); // tenant check
        return ResponseEntity.ok(interviewRepository.findByJobApplicationIdOrderByScheduledAtAsc(applicationId)
                .stream().map(InterviewResponse::from).toList());
    }

    @PostMapping
    @Transactional
    public ResponseEntity<InterviewResponse> schedule(@RequestBody InterviewRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Long companyId = requireCompanyId();
        JobApplication application = requireApplication(request.getJobApplicationId());
        if (application.getStatus() == ApplicationStatus.HIRED
                || application.getStatus() == ApplicationStatus.REJECTED
                || application.getStatus() == ApplicationStatus.WITHDRAWN) {
            throw new BadRequestException("This application is closed - reopen it before scheduling interviews");
        }
        if (request.getScheduledAt() == null) {
            throw new BadRequestException("Interview date/time is required");
        }
        if (request.getInterviewerId() == null) {
            throw new BadRequestException("An interviewer is required");
        }

        Company companyRef = new Company();
        companyRef.setId(companyId);

        Interview interview = Interview.builder()
                .company(companyRef)
                .jobApplication(application)
                .round(request.getRound() != null ? request.getRound() : Interview.Round.SCREENING)
                .scheduledAt(request.getScheduledAt())
                .durationMinutes(request.getDurationMinutes())
                .mode(request.getMode() != null ? request.getMode() : Interview.Mode.VIDEO)
                .meetingLink(request.getMeetingLink())
                .interviewer(resolveInterviewer(request.getInterviewerId(), companyId))
                .build();
        interview = interviewRepository.save(interview);

        // First scheduled round pulls the application forward in the funnel.
        if (application.getStatus() == ApplicationStatus.APPLIED
                || application.getStatus() == ApplicationStatus.SCREENING
                || application.getStatus() == ApplicationStatus.SHORTLISTED) {
            application.setStatus(ApplicationStatus.INTERVIEW_SCHEDULED);
        }

        // Email the candidate: they aren't platform users and get no in-app notification, so nothing otherwise tells them an interview was booked.
        try {
            Company fullCompany = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
            EmailBranding.Data branding = emailBranding.from(fullCompany);
            String details = "Round: " + interview.getRound()
                + " | When: " + interview.getScheduledAt()
                + " | Mode: " + interview.getMode()
                + (interview.getMeetingLink() != null && !interview.getMeetingLink().isBlank()
                    ? " | Link: " + interview.getMeetingLink() : "");
            // loadable(), not a null check: the candidate proxy is non-null and throws once the candidate is soft-deleted, and there is then no address to write to.
            var candidate = SoftDeletedProxies.loadable(application.getCandidate());
            if (candidate == null || candidate.getEmail() == null) {
                log.warn("Interview scheduled email skipped - no candidate address on application {}", application.getId());
            } else {
                emailService.sendInterviewScheduledEmail(
                    candidate.getEmail(), candidate.getName(), details, branding);
            }
        } catch (Exception ex) {
            log.warn("Interview scheduled email failed (interview still booked): {}", ex.getMessage());
        }

        return ResponseEntity.ok(InterviewResponse.from(interview));
    }

    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<InterviewResponse> reschedule(@PathVariable Long id, @RequestBody InterviewRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Interview interview = requireInterview(id);
        if (interview.getStatus() != Interview.Status.SCHEDULED) {
            throw new BadRequestException("Only a scheduled interview can be edited");
        }
        if (request.getRound() != null) interview.setRound(request.getRound());
        if (request.getScheduledAt() != null) interview.setScheduledAt(request.getScheduledAt());
        if (request.getDurationMinutes() != null) interview.setDurationMinutes(request.getDurationMinutes());
        if (request.getMode() != null) interview.setMode(request.getMode());
        if (request.getMeetingLink() != null) interview.setMeetingLink(request.getMeetingLink());
        if (request.getInterviewerId() != null) {
            interview.setInterviewer(resolveInterviewer(request.getInterviewerId(), requireCompanyId()));
        }
        return ResponseEntity.ok(InterviewResponse.from(interview));
    }

    @PatchMapping("/{id}/feedback")
    @Transactional
    public ResponseEntity<InterviewResponse> feedback(@PathVariable Long id, @RequestBody FeedbackRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Interview interview = requireInterview(id);
        if (interview.getStatus() == Interview.Status.CANCELLED) {
            throw new BadRequestException("A cancelled interview cannot take feedback");
        }
        if (request.getRating() != null && (request.getRating() < 1 || request.getRating() > 5)) {
            throw new BadRequestException("Rating must be between 1 and 5");
        }
        interview.setRating(request.getRating());
        interview.setStrengths(request.getStrengths());
        interview.setConcerns(request.getConcerns());
        interview.setRecommendation(request.getRecommendation());
        interview.setFeedbackAt(LocalDateTime.now());
        interview.setStatus(request.isNoShow() ? Interview.Status.NO_SHOW : Interview.Status.COMPLETED);

        // Last outstanding round done -> the application has been interviewed; a no-show doesn't count, so the recruiter decides what happens next.
        JobApplication application = applicationOf(interview);
        if (!request.isNoShow()
                && application.getStatus() == ApplicationStatus.INTERVIEW_SCHEDULED
                && !interviewRepository.existsByJobApplicationIdAndStatus(application.getId(), Interview.Status.SCHEDULED)) {
            application.setStatus(ApplicationStatus.INTERVIEWED);
        }
        return ResponseEntity.ok(InterviewResponse.from(interview));
    }

    @PatchMapping("/{id}/cancel")
    @Transactional
    public ResponseEntity<InterviewResponse> cancel(@PathVariable Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Interview interview = requireInterview(id);
        if (interview.getStatus() != Interview.Status.SCHEDULED) {
            throw new BadRequestException("Only a scheduled interview can be cancelled");
        }
        interview.setStatus(Interview.Status.CANCELLED);

        // Drop back to SHORTLISTED when this was the last outstanding round, so the application isn't stuck at INTERVIEW_SCHEDULED with nothing scheduled.
        JobApplication application = applicationOf(interview);
        if (application.getStatus() == ApplicationStatus.INTERVIEW_SCHEDULED
                && !interviewRepository.existsByJobApplicationIdAndStatus(application.getId(), Interview.Status.SCHEDULED)) {
            application.setStatus(ApplicationStatus.SHORTLISTED);
        }
        return ResponseEntity.ok(InterviewResponse.from(interview));
    }

    /**
     * The interview's application, via loadable() rather than a null check: the lazy proxy is non-null and throws
     * EntityNotFoundException once the application is soft-deleted (BaseEntity's {@code @SQLRestriction}), which
     * 500'd feedback and cancellation on an orphaned interview instead of saying what was wrong.
     */
    private JobApplication applicationOf(Interview interview) {
        JobApplication application = SoftDeletedProxies.loadable(interview.getJobApplication());
        if (application == null) {
            throw new BadRequestException("The application behind this interview has been deleted");
        }
        return application;
    }

    private Employee resolveInterviewer(Long interviewerId, Long companyId) {
        if (interviewerId == null) return null;
        return employeeRepository.findByIdAndCompanyId(interviewerId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Interviewer not found: " + interviewerId));
    }

    private Interview requireInterview(Long id) {
        return interviewRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Interview not found: " + id));
    }

    private JobApplication requireApplication(Long id) {
        return applicationRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    @Getter @Setter
    public static class InterviewRequest {
        private Long jobApplicationId;
        private Interview.Round round;
        private LocalDateTime scheduledAt;
        private Integer durationMinutes;
        private Interview.Mode mode;
        private String meetingLink;
        private Long interviewerId;
    }

    @Getter @Setter
    public static class FeedbackRequest {
        private Integer rating;
        private String strengths;
        private String concerns;
        private Interview.Recommendation recommendation;
        private boolean noShow;
    }

    @Getter @Setter
    public static class InterviewResponse {
        private Long id;
        private Long jobApplicationId;
        private String applicantName;
        private String jobTitle;
        private String applicationStatus;
        private Interview.Round round;
        private LocalDateTime scheduledAt;
        private Integer durationMinutes;
        private Interview.Mode mode;
        private String meetingLink;
        private Long interviewerId;
        private String interviewerName;
        private Interview.Status status;
        private Integer rating;
        private String strengths;
        private String concerns;
        private Interview.Recommendation recommendation;
        private LocalDateTime feedbackAt;

        /*
         * Associations go through SoftDeletedProxies, not != null checks: a lazy proxy to a soft-deleted row is
         * non-null and throws EntityNotFoundException as soon as it is read (BaseEntity's @SQLRestriction).
         * Deleting a candidate leaves their interviews live, which 500'd this list and every detail view;
         * applicantName falls back to the value denormalised on the application.
         */
        static InterviewResponse from(Interview i) {
            JobApplication a = SoftDeletedProxies.loadable(i.getJobApplication());
            var candidate = a == null ? null : SoftDeletedProxies.loadable(a.getCandidate());
            var posting = a == null ? null : SoftDeletedProxies.loadable(a.getJobPosting());
            InterviewResponse r = new InterviewResponse();
            r.id = i.getId();
            r.jobApplicationId = SoftDeletedProxies.id(i.getJobApplication());
            r.applicantName = candidate != null && candidate.getName() != null
                    ? candidate.getName() : a != null ? a.getApplicantName() : null;
            r.jobTitle = posting != null ? posting.getTitle() : null;
            r.applicationStatus = a != null && a.getStatus() != null ? a.getStatus().name() : null;
            r.round = i.getRound();
            r.scheduledAt = i.getScheduledAt();
            r.durationMinutes = i.getDurationMinutes();
            r.mode = i.getMode();
            r.meetingLink = i.getMeetingLink();
            r.interviewerId = SoftDeletedProxies.id(i.getInterviewer());
            r.interviewerName = EmployeeUserResolver.displayName(i.getInterviewer());
            r.status = i.getStatus();
            r.rating = i.getRating();
            r.strengths = i.getStrengths();
            r.concerns = i.getConcerns();
            r.recommendation = i.getRecommendation();
            r.feedbackAt = i.getFeedbackAt();
            return r;
        }
    }
}
