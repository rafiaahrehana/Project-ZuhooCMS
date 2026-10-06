package com.zuhoocms.modules.hrm.recruitment.offerletter;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.enums.LetterType;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeUserResolver;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;

import java.time.LocalDate;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import com.zuhoocms.modules.ai.support.PreparedPrompt;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.EmploymentLetterPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;

@Service
@RequiredArgsConstructor

public class OfferLetterServiceImpl implements OfferLetterService {

    private final OfferLetterRepository      letterRepository;
    private final EmployeeRepository         employeeRepository;
    private final JobApplicationRepository   jobApplicationRepository;
    private final CompanyRepository          companyRepository;
    private final SecurityUtil               securityUtil;
    private final AiService                  aiService;
    private final AiTransactionBoundary      aiTx;
    private final AuthorizationService       authorizationService;
    private final EmployeeUserResolver       userResolver;
    private final LetterEmployeeLookup       employeeLookup;

    /** OFFER and APPOINTMENT letters go to a recruitment candidate, not an employee. */
    private boolean isPreEmploymentLetter(LetterType type) {
        return type == LetterType.OFFER || type == LetterType.APPOINTMENT;
    }

    /** Recipient resolved in the validation phase, carried across the AI call by id. */
    private record LetterRecipient(Long employeeId, Long applicationId,
                                  String recipientName, String recipientEmail) {}

    /*
     * Three phases so the AI call isn't inside a transaction, which would hold a pooled DB connection for as long as the provider takes to answer (see AiTransactionBoundary): validate/resolve/build prompt [tx], generate body [no tx], persist [tx].
     * Entities are carried between phases by id and re-read in phase 3, since phase 1's are detached once it commits.
     */
    @Override
    public OfferLetterResponse create(OfferLetterRequest request) {
        authorizationService.checkPermission(PermissionCode.LETTER_CREATE);
        Long companyId = requireCompanyId();
        boolean candidateLetter = isPreEmploymentLetter(request.getLetterType());
        boolean needsAiContent = request.getContent() == null || request.getContent().isBlank();

        PreparedPrompt<LetterRecipient> prepared = aiTx.load(() -> {
            Employee employee = null;
            JobApplication application = null;
            String recipientName;
            String recipientEmail;

            if (candidateLetter) {
                // OFFER / APPOINTMENT: recipient is a recruitment candidate who hasn't joined yet.
                if (request.getJobApplicationId() == null) {
                    throw new BadRequestException(
                        request.getLetterType() + " letters must be addressed to a recruitment candidate");
                }
                application = jobApplicationRepository.findByIdAndCompanyId(request.getJobApplicationId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Candidate not found: " + request.getJobApplicationId()));
                // loadable(), not a null check: a proxy to a soft-deleted candidate is non-null and throws when read.
                var candidate = userResolver.loadable(application.getCandidate());
                recipientName = candidate != null && candidate.getName() != null
                    ? candidate.getName() : application.getApplicantName();
                recipientEmail = candidate != null ? candidate.getEmail() : null;
            } else {
                // All other letters: recipient is an existing employee.
                if (request.getEmployeeId() == null) {
                    throw new BadRequestException(
                        request.getLetterType() + " letters must be addressed to an employee");
                }
                employee = requireEmployeeIncludingDeparted(request.getEmployeeId(), companyId);
                // Through EmployeeUserResolver, not employee.getUser(): the lazy User proxy is non-null but throws
                // EntityNotFoundException the moment it is touched once the login is soft-deleted (see employeeName below).
                recipientName = userResolver.fullName(employee);
                recipientEmail = employeeEmail(employee);
            }

            if (request.getReferenceNumber() != null
                    && letterRepository.existsByCompanyIdAndReferenceNumber(companyId, request.getReferenceNumber())) {
                throw new BadRequestException("Reference number already exists: " + request.getReferenceNumber());
            }

            // Built here because both prompt builders read lazy associations (application.getJobPosting(), employee.getDesignation()/getUser()).
            String prompt = !needsAiContent ? null
                : candidateLetter
                    ? buildCandidatePrompt(companyId, application, request.getLetterType().name())
                    : buildLetterPrompt(companyId, employee, request.getLetterType().name());

            return new PreparedPrompt<>(
                new LetterRecipient(
                    employee != null ? employee.getId() : null,
                    application != null ? application.getId() : null,
                    recipientName, recipientEmail),
                prompt);
        });

        LetterRecipient recipient = prepared.payload();
        String content = needsAiContent
            ? aiService.generateRaw(AiFeature.EMPLOYMENT_LETTER, prepared.prompt())
            : request.getContent();

        return aiTx.persist(() -> {
            OfferLetter letter = OfferLetter.builder()
                .employee(recipient.employeeId() == null ? null
                    : employeeRepository.getReferenceById(recipient.employeeId()))
                .jobApplication(recipient.applicationId() == null ? null
                    : jobApplicationRepository.getReferenceById(recipient.applicationId()))
                .recipientName(recipient.recipientName())
                .recipientEmail(recipient.recipientEmail())
                .company(companyRef(companyId))
                .letterType(request.getLetterType())
                .referenceNumber(request.getReferenceNumber())
                .issueDate(request.getIssueDate())
                .content(content)
                .signedBy(request.getSignedBy())
                .createdBy(securityUtil.getCurrentUser())
                .issued(false)
                .build();

            letterRepository.save(letter);
            return OfferletterMapper.toLetterResponse(letter, employeeName(letter));
        });
    }

    /**
     * Display name for the letter's employee, taken from the denormalized recipientName on the row instead of the
     * lazy Employee -> User proxy: that proxy throws EntityNotFoundException under BaseEntity's
     * {@code @SQLRestriction("deleted = false")} as soon as the employee's login is soft-deleted, and works only
     * inside the transaction. recipientName was captured from the same user when the letter was created.
     */
    private static String employeeName(OfferLetter letter) {
        return letter.getEmployee() != null ? letter.getRecipientName() : null;
    }

    @Override
    @Transactional(readOnly = true)
    public OfferLetterResponse getById(Long id) {
        OfferLetter letter = findInTenant(id);
        // Without LETTER_VIEW, only your own issued letters: any colleague could otherwise read any salary/warning/termination letter by id.
        if (!authorizationService.hasPermission(PermissionCode.LETTER_VIEW)) {
            Long myEmployeeId = currentEmployeeId();
            // userResolver.id(), not letter.getEmployee().getId(): getId() on a proxy to a departed employee loads the
            // row and throws under @SQLRestriction, so the ownership check itself 500'd for a soft-deleted employee.
            boolean ownIssued = letter.isIssued() && myEmployeeId != null
                && myEmployeeId.equals(userResolver.id(letter.getEmployee()));
            if (!ownIssued) {
                throw new ForbiddenException("You can only view letters issued to you");
            }
        }
        return OfferletterMapper.toLetterResponse(letter, employeeName(letter));
    }

    private Long currentEmployeeId() {
        var user = securityUtil.getCurrentUser();
        return user == null ? null : employeeRepository.findByUserId(user.getId()).map(Employee::getId).orElse(null);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<OfferLetterResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LETTER_VIEW);
        return letterRepository.findByCompanyId(requireCompanyId(), pageable)
            .map(l -> OfferletterMapper.toLetterResponse(l, employeeName(l)));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<OfferLetterResponse> listForEmployee(Long employeeId, Pageable pageable) {
        if (authorizationService.hasPermission(PermissionCode.LETTER_VIEW)) {
            return letterRepository.findByCompanyIdAndEmployeeId(requireCompanyId(), employeeId, pageable)
                .map(l -> OfferletterMapper.toLetterResponse(l, employeeName(l)));
        }
        Long myEmployeeId = currentEmployeeId();
        if (myEmployeeId == null || !myEmployeeId.equals(employeeId)) {
            throw new ForbiddenException("You can only view your own letters");
        }
        return letterRepository.findByCompanyIdAndEmployeeIdAndIssuedTrue(requireCompanyId(), employeeId, pageable)
            .map(l -> OfferletterMapper.toLetterResponse(l, employeeName(l)));
    }

    @Override
    @Transactional
    public OfferLetterResponse issue(Long id) {
        authorizationService.checkPermission(PermissionCode.LETTER_UPDATE);
        OfferLetter letter = findInTenant(id);
        if (letter.isIssued()) throw new BadRequestException("Letter is already issued");
        letter.setIssued(true);
        return OfferletterMapper.toLetterResponse(letter, employeeName(letter));
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.LETTER_DELETE);
        OfferLetter letter = findInTenant(id);
        if (letter.isIssued()) throw new BadRequestException("Cannot delete an issued letter");
        letter.softDelete();
    }

    // No @Transactional on purpose: aiTx.load() commits before the provider call so no DB connection is held across it - see AiTransactionBoundary.
    @Override
    public OfferLetterDraftResponse draftWithAi(OfferLetterDraftRequest request) {
        authorizationService.checkPermission(PermissionCode.LETTER_CREATE);
        Long companyId = requireCompanyId();

        String prompt = aiTx.load(() -> {
            if (isPreEmploymentLetter(request.getLetterType())) {
                if (request.getJobApplicationId() == null) {
                    throw new BadRequestException(
                        request.getLetterType() + " letters must be addressed to a recruitment candidate");
                }
                JobApplication application = jobApplicationRepository
                    .findByIdAndCompanyId(request.getJobApplicationId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Candidate not found: " + request.getJobApplicationId()));
                return buildCandidatePrompt(companyId, application, request.getLetterType().name());
            }
            if (request.getEmployeeId() == null) {
                throw new BadRequestException(
                    request.getLetterType() + " letters must be addressed to an employee");
            }
            Employee employee = requireEmployeeIncludingDeparted(request.getEmployeeId(), companyId);
            return buildLetterPrompt(companyId, employee, request.getLetterType().name());
        });

        OfferLetterDraftResponse response = new OfferLetterDraftResponse();
        response.setContent(aiService.generateRaw(AiFeature.EMPLOYMENT_LETTER, prompt));
        return response;
    }

    private String buildCandidatePrompt(Long companyId, JobApplication application, String letterType) {
        Company company = companyRepository.findById(companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Company not found: " + companyId));

        // Same as buildLetterPrompt: both associations are lazy proxies over soft-deletable rows, so they go through the resolver.
        var candidate = userResolver.loadable(application.getCandidate());
        var posting = userResolver.loadable(application.getJobPosting());

        return EmploymentLetterPromptBuilder.builder()
            .setCompanyName(company.getCompanyName())
            .setEmployeeName(candidate != null && candidate.getName() != null
                ? candidate.getName() : application.getApplicantName())
            .setDesignation(posting != null ? posting.getTitle() : "Not specified")
            .setDepartment("Not specified")
            // The candidate hasn't joined, so there is no hire date: today stands in as the draft's proposed date, and the content is editable.
            .setJoiningDate(LocalDate.now())
            .setLetterType(letterType)
            .build();
    }

    /** Contact address for the employee: live login, else the soft-deleted user row, else the official work email. */
    private String employeeEmail(Employee employee) {
        var user = userResolver.liveUser(employee);
        if (user != null && user.getEmail() != null) return user.getEmail();
        var snapshot = userResolver.snapshot(employee.getId(), userResolver.companyId(employee));
        if (snapshot != null && snapshot.email() != null) return snapshot.email();
        return employee.getOfficialEmail();
    }

    /*
     * Every association here goes through EmployeeUserResolver: a lazy proxy to a soft-deleted row throws
     * EntityNotFoundException as soon as it is touched (BaseEntity's @SQLRestriction("deleted = false")), and a
     * null check does not help because the proxy itself is not null. An employee whose login was deactivated or
     * removed - exactly the one a relieving/experience letter is for - otherwise 500'd the draft.
     */
    private String buildLetterPrompt(Long companyId, Employee employee, String letterType) {
        Company company = companyRepository.findById(companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Company not found: " + companyId));

        var designation = userResolver.loadable(employee.getDesignation());
        var department = userResolver.loadable(employee.getDepartment());

        return EmploymentLetterPromptBuilder.builder()
            .setCompanyName(company.getCompanyName())
            .setEmployeeName(userResolver.fullName(employee))
            .setDesignation(designation != null ? designation.getName() : employee.getJobTitle())
            .setDepartment(department != null ? department.getName() : "Not specified")
            .setJoiningDate(employee.getHireDate())
            .setLetterType(letterType)
            .build();
    }

    /**
     * The letter's recipient, departed employees included, scoped to the caller's company.
     *
     * <p>{@code employeeRepository.findByIdAndCompanyId} cannot see them: {@code DELETE /api/employees/{id}}
     * soft-deletes the row and {@code BaseEntity}'s {@code @SQLRestriction("deleted = false")} then hides it, so
     * every letter endpoint 404'd for the person an EXPERIENCE / relieving / NOC letter is written for. Addressing a
     * departed employee is deliberate here and nowhere else - see {@link LetterEmployeeLookup}. Permission checks are
     * unchanged; this only widens which employee row can be found.
     */
    private Employee requireEmployeeIncludingDeparted(Long employeeId, Long companyId) {
        return employeeLookup.findIncludingDeparted(employeeId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));
    }

    private OfferLetter findInTenant(Long id) {
        return letterRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Employment letter not found: " + id));
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
