package com.zuhoocms.modules.hrm.attendance.timesheet;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.servicedesk.task.Task;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.servicedesk.task.TaskRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.TimesheetEntryPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
@lombok.extern.slf4j.Slf4j
public class TimesheetServiceImpl implements TimesheetService {

    private static final ObjectMapper COMPOSE_MAPPER = new ObjectMapper();

    private final TimesheetRepository timesheetRepository;
    private final EmployeeRepository  employeeRepository;
    private final TaskRepository      taskRepository;
    private final SecurityUtil        securityUtil;
    private final AuthorizationService authorizationService;
    private final AiService           aiService;

    /** One timesheet row is one work date, so more than 24 hours on it is never real. */
    private static final double MAX_HOURS_PER_DAY = 24.0;

    /** The DTO's @Min(0) only runs under a controller's @Valid; the AI agent's log_timesheet tool builds the request directly, so the rule lives here too. */
    private static void requireSaneHours(Double hours, boolean required) {
        if (hours == null) {
            if (required) throw new BadRequestException("Hours worked is required");
            return;
        }
        if (hours.isNaN() || hours < 0 || hours > MAX_HOURS_PER_DAY) {
            throw new BadRequestException("Hours worked must be between 0 and " + (int) MAX_HOURS_PER_DAY);
        }
    }

    @Override
    @Transactional
    public TimesheetResponse log(TimesheetRequest request) {
        requireSaneHours(request.getHoursWorked(), true);
        Long companyId = requireCompanyId();
        // Must be the record for the ACTIVE company: otherwise the entry is stamped with company A while being
        // attributed to the caller's company-B employee row (and checked for duplicates against it).
        Employee employee = currentEmployeeInCompany(companyId);

        if (timesheetRepository.findByCompanyIdAndEmployeeIdAndWorkDate(companyId, employee.getId(), request.getWorkDate()).isPresent()) {
            throw new BadRequestException("Timesheet already logged for " + request.getWorkDate());
        }

        // A soft-deleted entry still holds the (employee, work_date) unique key; reuse it as a fresh draft instead of failing the insert.
        Timesheet ts;
        if (timesheetRepository.reviveDeleted(companyId, employee.getId(), request.getWorkDate()) > 0) {
            ts = timesheetRepository.findByCompanyIdAndEmployeeIdAndWorkDate(companyId, employee.getId(), request.getWorkDate())
                .orElseThrow(() -> new ResourceNotFoundException("Timesheet not found for " + request.getWorkDate()));
            ts.setSubmitted(false);
            ts.setSubmittedAt(null);
            ts.setApproved(false);
            ts.setApprovedBy(null);
        } else {
            ts = new Timesheet();
        }
        ts.setEmployee(employee); ts.setCompany(companyRef(companyId)); ts.setWorkDate(request.getWorkDate()); ts.setStartTime(request.getStartTime() != null ? request.getStartTime().toLocalTime() : null); ts.setEndTime(request.getEndTime() != null ? request.getEndTime().toLocalTime() : null); ts.setHoursWorked(request.getHoursWorked()); ts.setBillableHours(request.getBillableHours() != null ? request.getBillableHours() : 0.0); ts.setWorkSummary(request.getDescription()); ts.setProjectName(request.getProjectName()); ts.setTaskDescription(request.getTaskDescription());

        requireTaskInTenant(request.getTaskId(), companyId);

        timesheetRepository.save(ts);
        return TimesheetMapper.toTimesheetResponse(ts);
    }

    @Override
    @Transactional(readOnly = true)
    public TimesheetResponse getById(Long id) {
        Timesheet ts = findInTenant(id);
        // findInTenant only proves same-company, so without this any tenant user could read anyone else's timesheet by incrementing an id.
        requireViewOrOwn(ts);
        return TimesheetMapper.toTimesheetResponse(ts);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<TimesheetResponse> listMine(Pageable pageable) {
        Long companyId = requireCompanyId();
        Employee emp = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        return timesheetRepository.findByCompanyIdAndEmployeeId(companyId, emp.getId(), pageable)
            .map(TimesheetMapper::toTimesheetResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<TimesheetResponse> listForEmployee(Long employeeId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.TIMESHEET_VIEW);
        return timesheetRepository.findByCompanyIdAndEmployeeId(requireCompanyId(), employeeId, pageable)
            .map(TimesheetMapper::toTimesheetResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<TimesheetResponse> listByDateRange(Long employeeId, LocalDate from, LocalDate to) {
        // This path never checked TIMESHEET_VIEW or ownership, so any tenant user could pull another employee's full timesheet history by passing their id.
        requireViewOrOwn(employeeId);
        return timesheetRepository.findByCompanyIdAndEmployeeIdAndWorkDateBetween(
                requireCompanyId(), employeeId, from, to)
            .stream().map(TimesheetMapper::toTimesheetResponse).toList();
    }

    @Override
    @Transactional
    public TimesheetResponse update(Long id, TimesheetRequest request) {
        Long companyId = requireCompanyId();
        Timesheet ts = findInTenant(id);
        // No TIMESHEET_UPDATE permission exists: a timesheet is self-reported, so only its own employee may edit it - otherwise any tenant user could rewrite another's unapproved hours.
        requireOwn(ts);
        if (ts.isApproved()) {
            throw new BadRequestException("Cannot edit an approved timesheet");
        }
        if (ts.isSubmitted()) {
            throw new BadRequestException("Cannot edit a timesheet that has been submitted for review");
        }
        if (request.getStartTime()    != null) ts.setStartTime(request.getStartTime().toLocalTime());
        if (request.getEndTime()      != null) ts.setEndTime(request.getEndTime().toLocalTime());
        requireSaneHours(request.getHoursWorked(), false);
        if (request.getHoursWorked()  != null) ts.setHoursWorked(request.getHoursWorked());
        if (request.getBillableHours()!= null) ts.setBillableHours(request.getBillableHours());
        if (request.getDescription()  != null) ts.setWorkSummary(request.getDescription());
        if (request.getProjectName()  != null) ts.setProjectName(request.getProjectName());
        if (request.getTaskDescription() != null) ts.setTaskDescription(request.getTaskDescription());
        // Matches create(): a Timesheet has no task column, so the id cannot be stored, but it is still validated rather
        // than silently swallowed - an unknown or out-of-tenant task id is a 404 on both paths, not an accepted no-op.
        requireTaskInTenant(request.getTaskId(), companyId);
        return TimesheetMapper.toTimesheetResponse(ts);
    }

    @Override
    @Transactional
    public int submitForReview() {
        Long companyId = requireCompanyId();
        Employee employee = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        List<Timesheet> draft = timesheetRepository.findByCompanyIdAndEmployeeIdAndSubmittedFalseAndApprovedFalse(
            companyId, employee.getId());
        LocalDateTime now = LocalDateTime.now();
        draft.forEach(ts -> { ts.setSubmitted(true); ts.setSubmittedAt(now); });
        return draft.size();
    }

    @Override
    @Transactional
    public TimesheetResponse approve(Long id) {
        authorizationService.checkPermission(PermissionCode.TIMESHEET_APPROVE);
        Timesheet ts = findInTenant(id);
        if (!ts.isSubmitted()) {
            throw new BadRequestException("This timesheet has not been submitted for review yet");
        }
        // Scoped to the timesheet's own tenant: resolving the approver's OTHER company's employee record gave a
        // non-matching id and waved the self-approval guard below through.
        Employee approver = currentEmployeeInCompany(requireCompanyId());
        if (ts.getEmployee() != null && ts.getEmployee().getId().equals(approver.getId())) {
            throw new BadRequestException("You cannot approve your own timesheet");
        }
        ts.setApproved(true);
        ts.setApprovedBy(approver.getUser());
        return TimesheetMapper.toTimesheetResponse(ts);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        Timesheet ts = findInTenant(id);
        // Same rationale as update(): no "edit someone else's" permission exists, so only its own employee may delete it.
        requireOwn(ts);
        if (ts.isApproved()) throw new BadRequestException("Cannot delete an approved timesheet");
        if (ts.isSubmitted()) throw new BadRequestException("Cannot delete a timesheet that has been submitted for review");
        ts.softDelete();
    }

    @Override
    public TimesheetComposeResponse composeEntry(TimesheetComposeRequest request) {
        String prompt = TimesheetEntryPromptBuilder.builder()
            .setProjectName(request.getProjectName())
            .setRoughNotes(request.getRoughNotes())
            .build();

        String raw = aiService.generateRaw(AiFeature.TIMESHEET_ENTRY, prompt);
        return parseCompose(raw, request.getRoughNotes());
    }

    private TimesheetComposeResponse parseCompose(String raw, String fallbackNotes) {
        TimesheetComposeResponse response = new TimesheetComposeResponse();
        try {
            String cleaned = raw.trim();
            if (cleaned.startsWith("```")) {
                cleaned = cleaned.replaceFirst("^```[a-zA-Z]*\\n?", "").replaceFirst("```\\s*$", "");
            }
            JsonNode node = COMPOSE_MAPPER.readTree(cleaned);
            response.setTaskDescription(node.path("taskDescription").asText(null));
            response.setDescription(node.path("description").asText(null));
        } catch (Exception ignored) {
            // Model returned invalid JSON - fall back to the raw text as the description rather than failing the request.
        }
        if (response.getTaskDescription() == null || response.getTaskDescription().isBlank()) {
            response.setTaskDescription(fallbackNotes.length() > 80
                ? fallbackNotes.substring(0, 77) + "..." : fallbackNotes);
        }
        if (response.getDescription() == null || response.getDescription().isBlank()) {
            response.setDescription(raw);
        }
        return response;
    }

    /** True if the timesheet belongs to the calling user's own employee record. */
    private boolean isOwn(Long timesheetEmployeeId) {
        Employee self = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId()).orElse(null);
        return self != null && timesheetEmployeeId != null && timesheetEmployeeId.equals(self.getId());
    }

    /** Guard for reads: caller must either hold TIMESHEET_VIEW or be looking at their own record. */
    private void requireViewOrOwn(Timesheet ts) {
        Long employeeId = ts.getEmployee() != null ? ts.getEmployee().getId() : null;
        requireViewOrOwn(employeeId);
    }

    private void requireViewOrOwn(Long employeeId) {
        if (authorizationService.hasPermission(PermissionCode.TIMESHEET_VIEW)) {
            return;
        }
        if (!isOwn(employeeId)) {
            throw new com.zuhoocms.shared.exception.ForbiddenException(
                    "Access denied: you can only view your own timesheets");
        }
    }

    /** Guard for writes: no TIMESHEET_UPDATE permission exists - only the owning employee may write. */
    private void requireOwn(Timesheet ts) {
        Long employeeId = ts.getEmployee() != null ? ts.getEmployee().getId() : null;
        if (!isOwn(employeeId)) {
            throw new com.zuhoocms.shared.exception.ForbiddenException(
                    "Access denied: you can only modify your own timesheets");
        }
    }

    private Timesheet findInTenant(Long id) {
        return timesheetRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Timesheet not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    /**
     * The caller's employee record in the active company. findByUserId alone is not enough: a user may hold an
     * employee record in more than one tenant, and the one it returns is whichever the database hands back.
     * Same rule as LeaveBalanceServiceImpl.listMine.
     */
    private Employee currentEmployeeInCompany(Long companyId) {
        Employee me = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
            .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        if (me.getCompany() == null || !me.getCompany().getId().equals(companyId)) {
            throw new BadRequestException("Employee profile does not belong to the active company");
        }
        return me;
    }

    /**
     * A Timesheet carries no task relation, so a supplied taskId cannot be persisted. It is still checked to exist inside
     * the caller's tenant, so a wrong or foreign id fails loudly instead of being dropped; create() and update() share this.
     */
    private void requireTaskInTenant(Long taskId, Long companyId) {
        if (taskId == null) return;
        Task task = taskRepository.findByIdAndCompanyId(taskId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Task not found: " + taskId));
        log.debug("Timesheet references task {} ({}); timesheets store no task link, so it is validated only.",
                task.getId(), companyId);
    }

    private Company companyRef(Long companyId) {
        Company c = new Company(); c.setId(companyId); return c;
    }
}

