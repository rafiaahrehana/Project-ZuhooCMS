package com.zuhoocms.modules.crm.lead;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.CrmSummaryPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.enums.*;
import com.zuhoocms.modules.crm.support.CrmSortWhitelist;
import com.zuhoocms.modules.crm.support.EmailMatching;
import com.zuhoocms.modules.crm.support.PhoneMatching;
import com.zuhoocms.modules.crm.support.TagResolver;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import com.zuhoocms.modules.ai.support.PreparedPrompt;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
@Slf4j
public class LeadServiceImpl implements LeadService {

    private final EmployeeRepository employeeRepository;
    private final CompanyServiceRepository companyServiceRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final LeadRepository leadRepository;
    private final com.zuhoocms.modules.crm.activity.CrmActivityRepository leadActivityRepository;
    private final LeadMapper leadMapper;
    private final NotificationService notificationService;
    private final com.zuhoocms.modules.crm.duplicate.DuplicateDetectionService duplicateDetectionService;
    private final com.zuhoocms.modules.crm.tag.TagRepository tagRepository;
    private final com.zuhoocms.modules.crm.opportunity.OpportunityService opportunityService;

    // Bound an open-ended date range; never compared unless the matching "...Set" flag is true, they exist only so Postgres can infer the parameter type. See LeadRepository.filterLeads.
    private static final java.time.LocalDate UNBOUNDED_EARLIEST = java.time.LocalDate.of(1900, 1, 1);
    private static final java.time.LocalDate UNBOUNDED_LATEST = java.time.LocalDate.of(9999, 12, 31);

    @Override
    @Transactional
    public LeadResponse createLead(LeadRequest request) {
        authorizationService.checkPermission(PermissionCode.LEAD_CREATE);
        Long companyId = requireCompanyId();

        // Normalised before both the check and the write, so the stored value and the duplicate query can never disagree - see EmailMatching / PhoneMatching.
        String email = EmailMatching.normalise(request.getEmail());
        String phone = PhoneMatching.normaliseForStorage(request.getPhone());
        checkLeadNotDuplicate(email, phone, companyId, null);

        Lead lead = Lead.builder()
                .contactName(request.getContactName())
                .companyName(request.getCompanyName())
                .email(email)
                .phone(phone)
                .industry(request.getIndustry())
                .jobTitle(request.getJobTitle())
                .notes(request.getNotes())
                .description(request.getDescription())
                .status(request.getStatus() != null ? request.getStatus() : LeadStatus.NEW)
                .source(request.getSource() != null ? request.getSource() : LeadSource.OTHER)
                .sourceOther(request.getSourceOther())
                .priority(request.getPriority() != null ? request.getPriority() : Priority.NORMAL)
                .estimatedValue(request.getEstimatedValue())
                .expectedCloseDate(request.getExpectedCloseDate())
                .company(companyRef(companyId))
                .build();

        if (request.getAssignedToId() != null) {
            Employee assignee = findEmployee(request.getAssignedToId(), companyId);
            lead.setAssignedTo(assignee);
        }

        if (request.getInterestedServiceId() != null) {
            lead.setInterestedService(
                    companyServiceRepository.findByIdAndCompanyId(request.getInterestedServiceId(), companyId)
                            .orElseThrow(() -> new ResourceNotFoundException(
                                    "Service not found: " + request.getInterestedServiceId())));
        }

        if (request.getTagIds() != null && !request.getTagIds().isEmpty()) {
            lead.setTags(TagResolver.resolve(tagRepository, request.getTagIds(), companyId));
        }

        Lead saved = leadRepository.save(lead);
        notifyAssignee(saved);

        LeadResponse response = leadMapper.toLeadResponse(saved);
        duplicateDetectionService
                .findPossibleDuplicateClient(saved.getCompanyName(), saved.getEmail(), saved.getPhone())
                .ifPresent(response::setPossibleDuplicate);
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public LeadResponse getLeadById(Long id) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        return leadMapper.toLeadResponse(findLeadInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> listLeads(LeadStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        Pageable paged = CrmSortWhitelist.withIdTiebreaker(pageable);
        return (status != null
                ? leadRepository.findByCompanyIdAndStatus(companyId, status, paged)
                : leadRepository.findByCompanyId(companyId, paged))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> listMyLeads(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        Employee emp = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
                .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        return leadRepository.findByCompanyIdAndAssignedToId(companyId, emp.getId(),
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional
    public LeadResponse updateLead(Long id, LeadUpdateRequest request) {
        authorizationService.checkPermission(PermissionCode.LEAD_UPDATE);
        Long companyId = requireCompanyId();
        Lead lead = findLeadInTenant(id);

        // DISQUALIFIED is frozen entirely; a CONVERTED lead still accepts who-the-contact-is and who-owns-it fields (typos, reassignment after a rep leaves) but not the commercial ones, which are the opportunity's job now.
        boolean converted = lead.isConverted();
        if (lead.getStatus() == LeadStatus.DISQUALIFIED) {
            throw new BadRequestException("Cannot edit a disqualified lead");
        }

        String email = EmailMatching.normalise(request.getEmail());
        String phone = PhoneMatching.normaliseForStorage(request.getPhone());
        // Both email and phone checked here as on create: update used to check only email, against a case-SENSITIVE query, so two leads could end up with the same address.
        checkLeadNotDuplicate(
                email != null && !email.equalsIgnoreCase(lead.getEmail()) ? email : null,
                phone != null && !samePhone(phone, lead.getPhone()) ? phone : null,
                companyId, lead.getId());

        if (request.getContactName() != null)
            lead.setContactName(request.getContactName());
        if (email != null)
            lead.setEmail(email);
        if (phone != null)
            lead.setPhone(phone);
        if (request.getJobTitle() != null)
            lead.setJobTitle(request.getJobTitle());

        if (!converted) {
            if (request.getCompanyName() != null)
                lead.setCompanyName(request.getCompanyName());
            if (request.getIndustry() != null)
                lead.setIndustry(request.getIndustry());
            if (request.getNotes() != null)
                lead.setNotes(request.getNotes());
            if (request.getDescription() != null)
                lead.setDescription(request.getDescription());
            if (request.getStatus() != null)
                lead.setStatus(request.getStatus());
            if (request.getSource() != null)
                lead.setSource(request.getSource());
            if (request.getSourceOther() != null)
                lead.setSourceOther(request.getSourceOther());
            if (request.getPriority() != null)
                lead.setPriority(request.getPriority());
            if (request.getEstimatedValue() != null)
                lead.setEstimatedValue(request.getEstimatedValue());
            if (request.getExpectedCloseDate() != null)
                lead.setExpectedCloseDate(request.getExpectedCloseDate());
            if (request.getTagIds() != null) {
                lead.setTags(TagResolver.resolve(tagRepository, request.getTagIds(), companyId));
            }
        }

        boolean reassigned = false;
        if (request.getAssignedToId() != null) {
            Employee assignee = findEmployee(request.getAssignedToId(), companyId);
            reassigned = lead.getAssignedTo() == null || !lead.getAssignedTo().getId().equals(assignee.getId());
            lead.setAssignedTo(assignee);
        }

        Lead saved = leadRepository.save(lead);
        if (reassigned) notifyAssignee(saved);
        return leadMapper.toLeadResponse(saved);
    }

    @Override
    @Transactional
    public void deleteLead(Long id) {
        authorizationService.checkPermission(PermissionCode.LEAD_DELETE);
        Lead lead = findLeadInTenant(id);
        // A converted lead is the Opportunity's sourceLead: soft-deleting it left that reference pointing at a row @SQLRestriction hides, breaking the lead-to-client trail.
        if (lead.isConverted()) {
            throw new BadRequestException(
                    "This lead has been converted to an opportunity and cannot be deleted. "
                            + "Delete the opportunity instead if it is no longer wanted.");
        }
        lead.setDeleted(true);
        lead.setDeletedAt(LocalDateTime.now());
        leadRepository.save(lead);

        // Saved explicitly, like the lead above: relying on dirty checking left the soft-delete at the mercy of whether the
        // activities were still managed when the transaction flushed, so a deleted lead could keep live activities.
        LocalDateTime deletedAt = LocalDateTime.now();
        List<com.zuhoocms.modules.crm.activity.CrmActivity> activities = lead.getActivities();
        if (activities != null && !activities.isEmpty()) {
            activities.forEach(activity -> {
                activity.setDeleted(true);
                activity.setDeletedAt(deletedAt);
            });
            leadActivityRepository.saveAll(activities);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> searchLeads(String keyword, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        return leadRepository.searchLeads(companyId, escapeLikeKeyword(keyword),
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    // '!' is the escape character in LeadRepository's ESCAPE '!' queries: unescaped, '!' throws and '%'/'_' match wrong rows. Mirrors GlobalSearchServiceImpl.escapeLikeKeyword.
    private String escapeLikeKeyword(String keyword) {
        if (keyword == null) return null;
        return keyword.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> filterLeads(LeadFilterRequest filter, Pageable pageable) {
        // Was ungated: a user blocked from GET /api/crm/leads got the same list by POSTing an empty body to /api/crm/leads/filter.
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();

        // Whitelisted with an id tiebreaker: sortBy handed straight to Sort.by threw PropertyReferenceException (a 500) and leaked which entity fields exist.
        if (filter.getSortBy() != null && !filter.getSortBy().isBlank()) {
            pageable = CrmSortWhitelist.pageable(pageable.getPageNumber(), pageable.getPageSize(),
                    CrmSortWhitelist.LEAD, filter.getSortBy(), filter.getSortDirection());
        } else {
            pageable = CrmSortWhitelist.withIdTiebreaker(pageable);
        }

        // The keyword is one predicate among many: it used to short-circuit to searchLeads() and silently discard status, source, priority, assignee and tag while the UI still showed them active.
        // "" rather than null when absent - see LeadRepository.filterLeads on Postgres being unable to type a null LIKE parameter.
        String keyword = filter.getKeyword() != null && !filter.getKeyword().isBlank()
                ? escapeLikeKeyword(filter.getKeyword().trim())
                : "";

        // Predicates, not short-circuits to their own repository methods, so they compose with the other filters; both views mean "still worth acting on", hence openOnly.
        boolean unassignedOnly = Boolean.TRUE.equals(filter.getIsUnassigned());
        boolean highPriorityOnly = Boolean.TRUE.equals(filter.getIsHighPriority());

        return leadRepository.filterLeads(
                companyId,
                filter.getStatus(),
                filter.getSource(),
                filter.getPriority(),
                filter.getAssignedToId(),
                filter.getTagId(),
                keyword,
                // Flag plus a never-null date - see the note on filterLeads.
                filter.getExpectedCloseDateFrom() != null,
                filter.getExpectedCloseDateFrom() != null
                        ? filter.getExpectedCloseDateFrom() : UNBOUNDED_EARLIEST,
                filter.getExpectedCloseDateTo() != null,
                filter.getExpectedCloseDateTo() != null
                        ? filter.getExpectedCloseDateTo() : UNBOUNDED_LATEST,
                Boolean.TRUE.equals(filter.getHasActivity()),
                Boolean.FALSE.equals(filter.getHasActivity()),
                Boolean.TRUE.equals(filter.getIsConverted()),
                Boolean.FALSE.equals(filter.getIsConverted()),
                unassignedOnly,
                highPriorityOnly,
                unassignedOnly || highPriorityOnly,
                pageable).map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findLeadsBySource(LeadSource source, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        return leadRepository.findByCompanyIdAndSource(companyId, source,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findLeadsByPriority(Priority priority, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        return leadRepository.findByCompanyIdAndPriority(companyId, priority,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findUnassignedLeads(Long companyId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        if (companyId == null) {
            companyId = requireCompanyId();
        }
        List<LeadStatus> closedStatuses = List.of(LeadStatus.DISQUALIFIED);
        return leadRepository.findUnassignedLeads(companyId, closedStatuses,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findHighPriorityOpenLeads(Long companyId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        if (companyId == null) {
            companyId = requireCompanyId();
        }
        List<LeadStatus> closedStatuses = List.of(LeadStatus.DISQUALIFIED);
        // expectedCloseDate is nullable and not a total order, so without withIdTiebreaker's id ASC rows repeat on one page and vanish from another.
        return leadRepository.findHighPriorityOpenLeads(companyId, closedStatuses,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findNeverContactedLeads(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        return leadRepository.findNeverContactedLeads(companyId,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeadResponse> findStalLeads(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        Long companyId = requireCompanyId();
        java.time.LocalDate stalDate = java.time.LocalDate.now().minusDays(30);
        List<LeadStatus> closedStatuses = List.of(LeadStatus.DISQUALIFIED);
        // Same cutoff in both column types: lastContactDate is a DATE, createdAt a timestamp the query falls back to; sorted by nullable lastActivityAt, so it needs the id tiebreaker.
        return leadRepository.findStalLeads(companyId, stalDate, stalDate.atStartOfDay(), closedStatuses,
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toLeadResponse);
    }

    // No Client or portal login is created here: a Client is created/linked when the Opportunity reaches Won (see OpportunityServiceImpl.changeStage).
    @Override
    @Transactional
    public com.zuhoocms.modules.crm.opportunity.OpportunityResponse convertToOpportunity(Long id, ConvertToOpportunityRequest request) {
        authorizationService.checkPermission(PermissionCode.LEAD_UPDATE);
        Lead lead = findLeadInTenant(id);

        if (lead.isConverted()) {
            throw new BadRequestException("Lead is already converted");
        }
        if (lead.getStatus() != LeadStatus.QUALIFIED) {
            throw new BadRequestException("Only a Qualified lead can be converted to an opportunity");
        }

        com.zuhoocms.modules.crm.opportunity.OpportunityRequest opportunityRequest =
                new com.zuhoocms.modules.crm.opportunity.OpportunityRequest();
        opportunityRequest.setName(request.getOpportunityName());
        opportunityRequest.setAmount(request.getExpectedValue());
        opportunityRequest.setExpectedCloseDate(request.getExpectedCloseDate());
        if (lead.getAssignedTo() != null) {
            opportunityRequest.setOwnerId(lead.getAssignedTo().getId());
        }

        // createFromLead() re-checks converted/Qualified and marks the lead converted itself; the checks above only fail this path faster.
        return opportunityService.createFromLead(id, opportunityRequest);
    }

    @Override
    @Transactional
    public com.zuhoocms.modules.crm.activity.CrmActivityResponse addActivity(Long leadId, com.zuhoocms.modules.crm.activity.CrmActivityRequest request) {
        // LEAD_UPDATE, not LEAD_VIEW: logging an activity writes lastActivityAt, lastContactDate and the staleness clock.
        authorizationService.checkPermission(PermissionCode.LEAD_UPDATE);
        Long companyId = requireCompanyId();
        Lead lead = findLeadInTenant(leadId);

        com.zuhoocms.modules.crm.activity.CrmActivity activity = com.zuhoocms.modules.crm.activity.CrmActivity.builder()
                .lead(lead)
                .performedBy(securityUtil.getCurrentUser())
                .type(request.getType() != null ? request.getType() : com.zuhoocms.modules.crm.activity.CrmActivityType.NOTE)
                .subject(request.getSubject())
                .description(request.getDescription())
                .activityDate(request.getActivityDate() != null ? request.getActivityDate() : LocalDateTime.now())
                // Without this, no endpoint wrote followUpAt, so the scheduler and the "Upcoming follow-ups" widget read a column only the demo seeder filled.
                .followUpAt(request.getFollowUpAt())
                .company(companyRef(companyId))
                .build();

        com.zuhoocms.modules.crm.activity.CrmActivity saved = leadActivityRepository.save(activity);

        lead.setLastActivityAt(LocalDateTime.now());
        lead.setStaleNotifiedAt(null);
        if (request.getType() == com.zuhoocms.modules.crm.activity.CrmActivityType.CALL ||
                request.getType() == com.zuhoocms.modules.crm.activity.CrmActivityType.MEETING ||
                request.getType() == com.zuhoocms.modules.crm.activity.CrmActivityType.EMAIL) {
            lead.setLastContactDate(LocalDateTime.now().toLocalDate());
        }
        leadRepository.save(lead);

        return leadMapper.toActivityResponse(saved);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<com.zuhoocms.modules.crm.activity.CrmActivityResponse> getActivities(Long leadId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        findLeadInTenant(leadId);
        return leadActivityRepository.findByLeadIdAndCompanyId(leadId, requireCompanyId(),
                        CrmSortWhitelist.withIdTiebreaker(pageable))
                .map(leadMapper::toActivityResponse);
    }

    @Override
    @Transactional
    public void deleteActivity(Long leadId, Long activityId) {
        authorizationService.checkPermission(PermissionCode.LEAD_UPDATE);
        findLeadInTenant(leadId);
        com.zuhoocms.modules.crm.activity.CrmActivity activity = leadActivityRepository.findById(activityId)
                .orElseThrow(() -> new ResourceNotFoundException("Activity not found"));

        if (!activity.getLead().getId().equals(leadId)) {
            throw new BadRequestException("Activity does not belong to this lead");
        }

        activity.setDeleted(true);
        activity.setDeletedAt(LocalDateTime.now());
        leadActivityRepository.save(activity);
    }

    @Override
    @Transactional(readOnly = true)
    public long countLeadsByStatus(LeadStatus status) {
        Long companyId = requireCompanyId();
        return leadRepository.countByCompanyIdAndStatusAndConvertedFalse(companyId, status);
    }

    @Override
    @Transactional(readOnly = true)
    public long countActiveLeads() {
        Long companyId = requireCompanyId();
        List<LeadStatus> closedStatuses = List.of(LeadStatus.DISQUALIFIED);
        return leadRepository.countActiveByCompanyId(companyId, closedStatuses);
    }

    @Override
    @Transactional(readOnly = true)
    public long countMyActiveLeads() {
        Long companyId = requireCompanyId();
        Employee emp = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
                .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        List<LeadStatus> closedStatuses = List.of(LeadStatus.DISQUALIFIED);
        return leadRepository.countActiveByAssignee(companyId, emp.getId(), closedStatuses);
    }

    // NOT_SUPPORTED overrides the class @Transactional so the provider call runs outside a transaction (see AiTransactionBoundary); reads and mapping, including lazy lead.getActivities(), must happen inside aiTx.load().
    @Override
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public LeadResponse summariseLead(Long id) {
        authorizationService.checkPermission(PermissionCode.LEAD_VIEW);
        PreparedPrompt<LeadResponse> prepared = aiTx.load(() -> {
            Lead lead = findLeadInTenant(id);
            return new PreparedPrompt<>(
                    leadMapper.toLeadResponse(lead),
                    CrmSummaryPromptBuilder.builder()
                            .setContactName(lead.getContactName())
                            .setCompanyName(lead.getCompanyName())
                            .setCurrentStatus(lead.getStatus().name())
                            .setInterestedService(lead.getInterestedService() != null ? lead.getInterestedService().getName() : null)
                            .setActivityHistory("Activities count: " + lead.getActivities().size())
                            .build());
        });

        LeadResponse response = prepared.payload();
        try {
            response.setAiSummary(aiService.generateRaw(AiFeature.CRM_LEAD_SUMMARY, prepared.prompt()));
        } catch (Exception e) {
            log.error("Failed to generate AI summary for lead with ID {}: {}", id, e.getMessage(), e);
            throw new BadRequestException("Failed to generate AI summary: " + e.getMessage());
        }

        return response;
    }

    private void notifyAssignee(Lead lead) {
        Employee assignee = lead.getAssignedTo();
        if (assignee == null || assignee.getUser() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.LEAD_ASSIGNED,
                "Lead Assigned",
                "Lead \"" + lead.getContactName() + "\" has been assigned to you.",
                "/crm/leads",
                assignee.getUser().getId(),
                lead.getCompany().getId()
        ));
    }

    private Lead findLeadInTenant(Long id) {
        Long companyId = requireCompanyId();
        return leadRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Lead not found with id: " + id));
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context found");
        }
        return companyId;
    }

    // Restricted to still-employed staff: company membership alone let leads be assigned to leavers, notifying a deactivated login.
    private Employee findEmployee(Long employeeId, Long companyId) {
        return employeeRepository.findAssignableByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Employee not found, or is no longer an active employee: " + employeeId));
    }

    /** Rejects a duplicate email (IgnoreCase) or phone (digits only, so "+966 50 123 4567" matches "0501234567"); values arrive normalised, null skips one, and {@code excludeId} stops an update colliding with itself. */
    private void checkLeadNotDuplicate(String email, String phone, Long companyId, Long excludeId) {
        if (email != null && leadRepository.existsByEmailIgnoringCase(email, companyId, excludeId)) {
            throw new BadRequestException("A lead with this email already exists in your company");
        }
        String phoneKey = PhoneMatching.matchKey(phone);
        if (phoneKey != null && leadRepository.existsByNormalisedPhone(phoneKey, companyId, excludeId)) {
            throw new BadRequestException("A lead with this phone number already exists in your company");
        }
    }

    /** Two phone strings that reduce to the same digits are the same number. */
    private boolean samePhone(String a, String b) {
        String keyA = PhoneMatching.matchKey(a);
        String keyB = PhoneMatching.matchKey(b);
        return keyA != null && keyA.equals(keyB);
    }

    private Company companyRef(Long companyId) {
        Company company = new Company();
        company.setId(companyId);
        return company;
    }

    // No hand-rolled validation here: LeadRequest's @NotBlank/@Size/@Email under the controller's @Valid is the single authority, and the old ^[A-Za-z0-9+_.-]+@(.+)$ regex disagreed with @Email in both directions.
}
