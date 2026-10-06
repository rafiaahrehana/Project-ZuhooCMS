package com.zuhoocms.modules.hrm.performance;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.PerformanceReviewPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import com.zuhoocms.modules.ai.support.PreparedPrompt;

import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.enums.TaskStatus;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceRepository;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.modules.servicedesk.servicereview.ServiceReviewRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.servicedesk.task.TaskRepository;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;
import java.util.stream.Stream;

@Slf4j
@Service
@RequiredArgsConstructor
public class PerformanceServiceImpl implements PerformanceService {

    private final PerformanceReviewRepository reviewRepository;
    private final EmployeeRepository employeeRepository;
    private final CompanyRepository companyRepository;
    private final SecurityUtil securityUtil;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final AuthorizationService authorizationService;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    // Sources for the objective KPI block, read-only: performance never writes to these modules.
    private final AttendanceRepository attendanceRepository;
    private final LeaveRequestRepository leaveRequestRepository;
    private final TaskRepository taskRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final ServiceReviewRepository serviceReviewRepository;
    private final PerformanceReviewAttachmentRepository attachmentRepository;
    private final NotificationService notificationService;

    @Override
    @Transactional
    public PerformanceReviewResponse create(PerformanceReviewRequest request) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_CREATE);
        Long companyId = requireCompanyId();
        Employee employee = employeeRepository.findByIdAndCompanyId(request.getEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + request.getEmployeeId()));
        // Scoped: reviewedBy is stored on a review stamped with companyId, and the response exposes it, so a
        // reviewer resolved from another tenant put a foreign employee on this company's review.
        Employee reviewer = employeeRepository.findByUserIdAndCompanyId(securityUtil.getCurrentUser().getId(), companyId)
                .orElseThrow(() -> new BadRequestException("Employee profile not found"));

        PerformanceReview review = PerformanceReview.builder()
                .employee(employee)
                .company(companyRef(companyId))
                .reviewedBy(reviewer)
                .reviewPeriodStart(request.getReviewPeriodStart())
                .reviewPeriodEnd(request.getReviewPeriodEnd())
                .scoreWorkQuality(request.getScoreWorkQuality())
                .scoreProductivity(request.getScoreProductivity())
                .scoreCommunication(request.getScoreCommunication())
                .scoreTeamwork(request.getScoreTeamwork())
                .scoreInitiative(request.getScoreInitiative())
                .scorePunctuality(request.getScorePunctuality())
                .scoreLeadership(request.getScoreLeadership())
                .scoreProblemSolving(request.getScoreProblemSolving())
                .scoreInnovation(request.getScoreInnovation())
                // calculateOverall skips nulls, so a review leaving some competencies blank still averages correctly.
                .overallScore(calculateOverall(
                        request.getScoreWorkQuality(), request.getScoreProductivity(),
                        request.getScoreCommunication(), request.getScoreTeamwork(),
                        request.getScoreInitiative(), request.getScorePunctuality(),
                        request.getScoreLeadership(), request.getScoreProblemSolving(),
                        request.getScoreInnovation()
                ))
                .strengths(request.getStrengths())
                .areasForImprovement(request.getAreasForImprovement())
                .goalsForNextPeriod(request.getGoalsForNextPeriod())
                .comments(request.getComments())
                .performanceLevel(request.getPerformanceLevel())
                .promotionRecommendation(request.getPromotionRecommendation())
                .promotionReadiness(request.getPromotionReadiness())
                .salaryIncrement(request.getSalaryIncrement())
                .employmentStatusRecommendation(request.getEmploymentStatusRecommendation())
                .goalCompletionPercent(request.getGoalCompletionPercent())
                .trainingRecommendation(request.getTrainingRecommendation())
                .recognition(request.getRecognition())
                .goals(request.getGoals())
                .build();

        reviewRepository.save(review);
        
        if (employee.getUser() != null) {
            try {
                Company fullCompany = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
                EmailBranding.Data branding = emailBranding.from(fullCompany);
                emailService.sendPerformanceReviewEmail(employee.getUser().getEmail(), employee.getUser().getFirstName(), branding);
                
            } catch (Exception ex) {
                // Best-effort: a failed email must not roll back the review.
                log.warn("Performance review email failed (review still saved): {}", ex.getMessage());
            }
        }

        return PerformanceMapper.toPerformanceReviewResponse(review);
    }

    @Override
    @Transactional(readOnly = true)
    public PerformanceReviewResponse getById(Long id) {
        PerformanceReview review = findInTenant(id);
        boolean canViewOthers = authorizationService.hasPermission(PermissionCode.PERFORMANCE_VIEW);
        // Without PERFORMANCE_VIEW the caller is the subject (findInTenant enforces that).
        // An in-progress review is the reviewers' working draft, not yet the employee's record.
        if (!canViewOthers && !review.isFinalised()) {
            throw new ResourceNotFoundException("Performance review not found: " + id);
        }
        return toResponseForViewer(review, canViewOthers);
    }

    /** salaryIncrement and employmentStatusRecommendation (e.g. PIP / TERMINATE) are management recommendations: only PERFORMANCE_VIEW holders see them. */
    private PerformanceReviewResponse toResponseForViewer(PerformanceReview review, boolean canViewOthers) {
        PerformanceReviewResponse response = PerformanceMapper.toPerformanceReviewResponse(review);
        if (!canViewOthers) {
            response.setSalaryIncrement(null);
            response.setEmploymentStatusRecommendation(null);
        }
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PerformanceReviewResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_VIEW);
        return reviewRepository.findByCompanyId(requireCompanyId(), pageable)
                .map(PerformanceMapper::toPerformanceReviewResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PerformanceReviewResponse> listForEmployee(Long employeeId, Pageable pageable) {
        // Without this an employee could list any colleague's reviews by id.
        guardOwnReviewAccess(employeeId);
        boolean canViewOthers = authorizationService.hasPermission(PermissionCode.PERFORMANCE_VIEW);
        Page<PerformanceReview> page = canViewOthers
                ? reviewRepository.findByCompanyIdAndEmployeeId(requireCompanyId(), employeeId, pageable)
                : reviewRepository.findByCompanyIdAndEmployeeIdAndFinalisedTrue(requireCompanyId(), employeeId, pageable);
        return page.map(r -> toResponseForViewer(r, canViewOthers));
    }

    @Override
    @Transactional
    public PerformanceReviewResponse update(Long id, PerformanceReviewRequest request) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_UPDATE);
        PerformanceReview review = findInTenant(id);
        if (review.isFinalised()) throw new BadRequestException("Cannot edit a finalised review");
        // Scores and recommendations must not move once the review reaches HR/final approval: they are what is being approved.
        PerformanceStage stage = review.getStage() != null ? review.getStage() : PerformanceStage.SELF_ASSESSMENT;
        if (stage != PerformanceStage.SELF_ASSESSMENT && stage != PerformanceStage.MANAGER_REVIEW) {
            throw new BadRequestException(
                    "A review can only be edited during self-assessment or manager review (current stage: " + stage + ")");
        }
        if (request.getReviewPeriodStart() != null) review.setReviewPeriodStart(request.getReviewPeriodStart());
        if (request.getReviewPeriodEnd() != null)   review.setReviewPeriodEnd(request.getReviewPeriodEnd());
        if (review.getReviewPeriodStart() != null && review.getReviewPeriodEnd() != null
                && review.getReviewPeriodEnd().isBefore(review.getReviewPeriodStart())) {
            throw new BadRequestException("Review period end must be on or after the start");
        }

        if (request.getScoreWorkQuality() != null)    review.setScoreWorkQuality(request.getScoreWorkQuality());
        if (request.getScoreProductivity() != null)   review.setScoreProductivity(request.getScoreProductivity());
        if (request.getScoreCommunication() != null)  review.setScoreCommunication(request.getScoreCommunication());
        if (request.getScoreTeamwork() != null)       review.setScoreTeamwork(request.getScoreTeamwork());
        if (request.getScoreInitiative() != null)     review.setScoreInitiative(request.getScoreInitiative());
        if (request.getScorePunctuality() != null)    review.setScorePunctuality(request.getScorePunctuality());
        if (request.getStrengths() != null)           review.setStrengths(request.getStrengths());
        if (request.getAreasForImprovement() != null) review.setAreasForImprovement(request.getAreasForImprovement());
        if (request.getGoalsForNextPeriod() != null)  review.setGoalsForNextPeriod(request.getGoalsForNextPeriod());
        if (request.getComments() != null)            review.setComments(request.getComments());
        if (request.getScoreLeadership() != null)     review.setScoreLeadership(request.getScoreLeadership());
        if (request.getScoreProblemSolving() != null) review.setScoreProblemSolving(request.getScoreProblemSolving());
        if (request.getScoreInnovation() != null)     review.setScoreInnovation(request.getScoreInnovation());

        if (request.getPerformanceLevel() != null)         review.setPerformanceLevel(request.getPerformanceLevel());
        if (request.getPromotionRecommendation() != null)  review.setPromotionRecommendation(request.getPromotionRecommendation());
        if (request.getPromotionReadiness() != null)       review.setPromotionReadiness(request.getPromotionReadiness());
        if (request.getSalaryIncrement() != null)          review.setSalaryIncrement(request.getSalaryIncrement());
        if (request.getEmploymentStatusRecommendation() != null)
            review.setEmploymentStatusRecommendation(request.getEmploymentStatusRecommendation());
        if (request.getGoalCompletionPercent() != null)    review.setGoalCompletionPercent(request.getGoalCompletionPercent());
        if (request.getTrainingRecommendation() != null)   review.setTrainingRecommendation(request.getTrainingRecommendation());
        if (request.getRecognition() != null)              review.setRecognition(request.getRecognition());
        if (request.getGoals() != null)                    review.setGoals(request.getGoals());

        review.setOverallScore(calculateOverall(
                review.getScoreWorkQuality(), review.getScoreProductivity(),
                review.getScoreCommunication(), review.getScoreTeamwork(),
                review.getScoreInitiative(), review.getScorePunctuality(),
                review.getScoreLeadership(), review.getScoreProblemSolving(),
                review.getScoreInnovation()
        ));

        reviewRepository.save(review);
        return PerformanceMapper.toPerformanceReviewResponse(review);
    }

    @Override
    @Transactional
    public PerformanceReviewResponse finalise(Long id) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_UPDATE);
        PerformanceReview review = findInTenant(id);
        if (review.isFinalised()) throw new BadRequestException("Review is already finalised");
        // finalise() is only the final sign-off; it used to jump to COMPLETED from any stage, skipping the approval chain.
        if (review.getStage() != PerformanceStage.FINAL_APPROVAL) {
            throw new BadRequestException("A review can only be finalised from the final approval stage (current stage: "
                    + (review.getStage() != null ? review.getStage() : PerformanceStage.SELF_ASSESSMENT) + ")");
        }
        requireSeparateApprover(review, PerformanceStage.FINAL_APPROVAL);
        var finalUser = securityUtil.getCurrentUser();
        review.setFinalApprovalAt(LocalDateTime.now());
        review.setFinalApprovalBy(currentUserName());
        review.setFinalApprovalByUserId(finalUser != null ? finalUser.getId() : null);
        review.setFinalised(true);
        review.setStage(PerformanceStage.COMPLETED);
        notifyFinalised(review);
        return PerformanceMapper.toPerformanceReviewResponse(review);
    }

    /** Signs off the current stage and moves to the next, stamping who and when; clearing the last stage sets `finalised`, so there is a single path to a final review. */
    @Override
    @Transactional
    public PerformanceReviewResponse advanceStage(Long id) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_UPDATE);
        PerformanceReview review = findInTenant(id);

        if (review.isFinalised() || review.getStage() == PerformanceStage.COMPLETED) {
            throw new BadRequestException("Review is already complete");
        }

        String actor = currentUserName();
        LocalDateTime now = LocalDateTime.now();
        PerformanceStage current = review.getStage() != null
            ? review.getStage() : PerformanceStage.SELF_ASSESSMENT;

        requireSeparateApprover(review, current);
        var actorUser = securityUtil.getCurrentUser();
        Long actorId = actorUser != null ? actorUser.getId() : null;

        switch (current) {
            case SELF_ASSESSMENT -> { review.setSelfAssessmentAt(now); review.setSelfAssessmentBy(actor); review.setSelfAssessmentByUserId(actorId); }
            case MANAGER_REVIEW  -> { review.setManagerReviewAt(now);  review.setManagerReviewBy(actor);  review.setManagerReviewByUserId(actorId); }
            case HR_APPROVAL     -> { review.setHrApprovalAt(now);     review.setHrApprovalBy(actor);     review.setHrApprovalByUserId(actorId); }
            case FINAL_APPROVAL  -> { review.setFinalApprovalAt(now);  review.setFinalApprovalBy(actor);  review.setFinalApprovalByUserId(actorId); }
            case COMPLETED       -> throw new BadRequestException("Review is already complete");
        }

        PerformanceStage next = current.next();
        review.setStage(next);
        if (next == PerformanceStage.COMPLETED) {
            review.setFinalised(true);
            notifyFinalised(review);
        } else {
            notifyStageAdvance(review, next);
        }

        reviewRepository.save(review);
        return PerformanceMapper.toPerformanceReviewResponse(review);
    }

    /**
     * Separation of duties: the employee under review can never sign off the manager, HR or final stage of their own review.
     * HR and final approval must come from someone other than whoever signed the preceding stage, except the company owner, so a one-approver company can still complete a review.
     */
    private void requireSeparateApprover(PerformanceReview review, PerformanceStage stage) {
        if (stage == PerformanceStage.SELF_ASSESSMENT || stage == PerformanceStage.COMPLETED) return;
        var user = securityUtil.getCurrentUser();
        if (user == null) return;
        Employee subject = review.getEmployee();
        if (subject != null && subject.getUser() != null && user.getId().equals(subject.getUser().getId())) {
            throw new ForbiddenException("You cannot approve your own performance review");
        }
        Long previousActor = switch (stage) {
            case HR_APPROVAL -> review.getManagerReviewByUserId();
            case FINAL_APPROVAL -> review.getHrApprovalByUserId();
            default -> null;
        };
        if (previousActor != null && previousActor.equals(user.getId()) && !isCompanyOwner(review, user.getId())) {
            throw new BadRequestException("The " + stage.name().replace('_', ' ').toLowerCase()
                    + " must be signed by someone other than the previous approver");
        }
    }

    private boolean isCompanyOwner(PerformanceReview review, Long userId) {
        User owner = ownerOf(review.getCompany().getId());
        return owner != null && owner.getId().equals(userId);
    }

    private String currentUserName() {
        var user = securityUtil.getCurrentUser();
        return user != null ? user.getFullName() : "System";
    }

    /** Notifies on stage changes: advanceStage()/finalise() used to flip state silently, so the next approver and the employee were never told. */
    private void notifyStageAdvance(PerformanceReview review, PerformanceStage next) {
        Employee employee = review.getEmployee();
        // No dedicated HR recipient list exists yet, so HR/final approval notifies the company owner, the same fallback leave approvals use.
        User recipient = next == PerformanceStage.MANAGER_REVIEW && employee.getReportingManager() != null
                ? employee.getReportingManager().getUser()
                : ownerOf(review.getCompany().getId());
        if (recipient == null) return;

        String subject = employee.getUser() != null ? employee.getUser().getFullName() : "An employee";
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.PERFORMANCE_REVIEW_STAGE,
                "Performance review awaiting your review",
                subject + "'s performance review has moved to " + next.name().replace('_', ' ') + " and needs your action",
                "/performance/" + review.getId(),
                recipient.getId(),
                review.getCompany().getId()));
    }

    private void notifyFinalised(PerformanceReview review) {
        Employee employee = review.getEmployee();
        User recipient = employee.getUser();
        if (recipient == null) return;

        notificationService.send(CreateNotificationRequest.of(
                NotificationType.PERFORMANCE_REVIEW_FINALISED,
                "Your performance review is finalised",
                "Your performance review for " + review.getReviewPeriodStart() + " to " + review.getReviewPeriodEnd()
                        + " has been completed and finalised.",
                "/performance/" + review.getId(),
                recipient.getId(),
                review.getCompany().getId()));
    }

    private User ownerOf(Long companyId) {
        Company company = companyRepository.findById(companyId).orElse(null);
        return company != null ? company.getOwner() : null;
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_DELETE);
        PerformanceReview review = findInTenant(id);
        if (review.isFinalised()) throw new BadRequestException("Cannot delete a finalised review");
        review.softDelete();
    }

    @Override
    // Reads and mapping run in aiTx.load(), which commits before the provider call so no DB connection is held across it - see AiTransactionBoundary.
    // The lazy employee/user/designation associations must be read inside the callback.
    public PerformanceReviewResponse summarise(Long id) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_VIEW);

        PreparedPrompt<PerformanceReviewResponse> prepared = aiTx.load(() -> {
            PerformanceReview review = findInTenant(id);
            PerformanceReviewResponse dto = PerformanceMapper.toPerformanceReviewResponse(review);

            if (review.getOverallScore() == null) {
                throw new BadRequestException("Fill in at least one KPI score before generating an AI summary");
            }
            Employee employee = review.getEmployee();

            return new PreparedPrompt<>(dto, PerformanceReviewPromptBuilder.builder()
                .setEmployeeName(employee.getUser().getFullName())
                .setDesignation(employee.getDesignation() != null ? employee.getDesignation().getName() : employee.getJobTitle())
                .setReviewPeriod(review.getReviewPeriodStart() + " to " + review.getReviewPeriodEnd())
                .setOverallScore((int) Math.round(review.getOverallScore()))
                .setStrengths(review.getStrengths())
                .setAreasForImprovement(review.getAreasForImprovement())
                .setGoalsForNextPeriod(review.getGoalsForNextPeriod())
                .build());
        });

        PerformanceReviewResponse response = prepared.payload();
        response.setAiSummary(aiService.generateRaw(AiFeature.PERFORMANCE_REVIEW, prepared.prompt()));
        return response;
    }

    private PerformanceReview findInTenant(Long id) {
        PerformanceReview review = reviewRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Performance review not found: " + id));
        guardOwnReviewAccess(review.getEmployee() != null ? review.getEmployee().getId() : null);
        return review;
    }

    /** Tenant scoping alone would let any employee read a colleague's review by changing the id in the URL; PERFORMANCE_VIEW means "may see other people's", everyone else only their own. */
    private void guardOwnReviewAccess(Long subjectEmployeeId) {
        if (authorizationService.hasPermission(PermissionCode.PERFORMANCE_VIEW)) {
            return;
        }
        Long myEmployeeId = employeeRepository
                .findByUserId(securityUtil.getCurrentUser().getId())
                .map(Employee::getId)
                .orElse(null);

        if (myEmployeeId == null || subjectEmployeeId == null
                || !myEmployeeId.equals(subjectEmployeeId)) {
            throw new ForbiddenException("You can only view your own performance reviews");
        }
    }


    /** Objective KPIs aggregated live from the modules that own the data; deliberately not stored on the review, which would freeze them at that day's data. */
    @Override
    @Transactional(readOnly = true)
    public PerformanceKpiResponse kpisForEmployee(Long employeeId, LocalDate from, LocalDate to) {
        // Same rule as reviews: PERFORMANCE_VIEW for other people's, own always visible; a flat checkPermission() would lock employees out of their own counts.
        guardOwnReviewAccess(employeeId);
        Long companyId = requireCompanyId();

        // Confirms the employee is in this tenant before reading anything else.
        employeeRepository.findByIdAndCompanyId(employeeId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));

        if (from == null || to == null) throw new BadRequestException("Both from and to dates are required");
        if (to.isBefore(from)) throw new BadRequestException("'to' must not be before 'from'");

        LocalDateTime fromTs = from.atStartOfDay();
        LocalDateTime toTs = to.plusDays(1).atStartOfDay(); // half-open, so the last day counts

        long present = countAttendance(employeeId, AttendanceStatus.PRESENT, from, to);
        long late = countAttendance(employeeId, AttendanceStatus.LATE, from, to);
        long wfh = countAttendance(employeeId, AttendanceStatus.WORK_FROM_HOME, from, to);
        long halfDay = countAttendance(employeeId, AttendanceStatus.HALF_DAY, from, to);
        long absent = countAttendance(employeeId, AttendanceStatus.ABSENT, from, to);
        long onLeave = countAttendance(employeeId, AttendanceStatus.ON_LEAVE, from, to);

        // LATE and WORK_FROM_HOME count as present; weekends and holidays are excluded from the denominator so time off doesn't dilute the percentage.
        long attended = present + late + wfh + halfDay;
        long workingDays = attended + absent + onLeave;
        Double attendancePercent = workingDays == 0
            ? null
            : Math.round((attended * 1000.0) / workingDays) / 10.0;

        Integer leaveDays = leaveRequestRepository
            .sumApprovedLeaveDaysInRange(companyId, employeeId, from, to);

        long tasksCompleted = taskRepository
            .countByCompanyIdAndAssignedEmployeeIdAndStatusAndCompletedAtBetween(
                companyId, employeeId, TaskStatus.COMPLETED, fromTs, toTs);

        long projectsCompleted = serviceRequestRepository
            .countByCompanyIdAndAssignedEmployeeIdAndStatusAndCompletedAtBetween(
                companyId, employeeId, ServiceRequestStatus.COMPLETED, fromTs, toTs);

        Double csat = serviceReviewRepository
            .findAverageRatingByStaffInRange(companyId, employeeId, fromTs, toTs)
            .map(v -> Math.round(v * 10.0) / 10.0)
            .orElse(null);

        return PerformanceKpiResponse.builder()
            .employeeId(employeeId)
            .periodStart(from)
            .periodEnd(to)
            .daysPresent(attended)
            .daysAbsent(absent)
            .workingDaysRecorded(workingDays)
            .attendancePercent(attendancePercent)
            .lateArrivals(late)
            .leaveDaysTaken(leaveDays != null ? leaveDays : 0)
            .tasksCompleted(tasksCompleted)
            .projectsCompleted(projectsCompleted)
            .customerSatisfaction(csat)
            .build();
    }

    @Override
    @Transactional(readOnly = true)
    public List<PerformanceAttachmentDtos.AttachmentResponse> listAttachments(Long reviewId) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_VIEW);
        findInTenant(reviewId); // tenant guard
        return attachmentRepository.findByReviewIdAndCompanyIdOrderByCreatedAtDesc(reviewId, requireCompanyId())
            .stream().map(PerformanceAttachmentDtos::toResponse).toList();
    }

    @Override
    @Transactional
    public PerformanceAttachmentDtos.AttachmentResponse addAttachment(
            Long reviewId, PerformanceAttachmentDtos.AttachmentRequest request) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_UPDATE);
        PerformanceReview review = findInTenant(reviewId);
        // A finalised review is a signed record; its evidence must not change.
        if (review.isFinalised()) throw new BadRequestException("Cannot attach to a finalised review");

        PerformanceReviewAttachment a = PerformanceReviewAttachment.builder()
            .review(review)
            .company(companyRef(requireCompanyId()))
            .fileName(request.getFileName())
            .fileUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getFileUrl()))
            .fileType(request.getFileType())
            .fileSizeBytes(request.getFileSizeBytes())
            .label(request.getLabel())
            .uploadedBy(securityUtil.getCurrentUser())
            .build();

        attachmentRepository.save(a);
        return PerformanceAttachmentDtos.toResponse(a);
    }

    @Override
    @Transactional
    public void deleteAttachment(Long reviewId, Long attachmentId) {
        authorizationService.checkPermission(PermissionCode.PERFORMANCE_UPDATE);
        PerformanceReview review = findInTenant(reviewId);
        if (review.isFinalised()) throw new BadRequestException("Cannot modify a finalised review");

        PerformanceReviewAttachment a = attachmentRepository
            .findByIdAndCompanyId(attachmentId, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Attachment not found: " + attachmentId));

        // Guards against deleting an attachment by passing someone else's review id.
        if (a.getReview() == null || !a.getReview().getId().equals(reviewId)) {
            throw new BadRequestException("Attachment does not belong to this review");
        }
        a.softDelete();
    }

    private long countAttendance(Long employeeId, AttendanceStatus status, LocalDate from, LocalDate to) {
        return attendanceRepository
            .countByEmployeeIdAndStatusAndAttendanceDateBetween(employeeId, status, from, to);
    }

    private Double calculateOverall(Integer... scores) {
        List<Integer> present = Stream.of(scores)
                .filter(Objects::nonNull)
                .toList();
        if (present.isEmpty()) return null;
        double avg = present.stream().mapToInt(Integer::intValue).average().orElse(0);
        return Math.round(avg * 10.0) / 10.0;
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