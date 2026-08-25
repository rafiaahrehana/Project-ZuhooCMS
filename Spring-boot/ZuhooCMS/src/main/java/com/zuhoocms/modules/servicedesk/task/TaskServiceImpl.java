package com.zuhoocms.modules.servicedesk.task;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRepository;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.enums.ServiceRequestPriority;
import com.zuhoocms.enums.TaskStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor

public class TaskServiceImpl implements TaskService {

    private final TaskRepository taskRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final EmployeeRepository employeeRepository;
    private final WorkflowStageRepository workflowStageRepository;
    private final NotificationService notificationService;
    private final SecurityUtil securityUtil;

    @Override
    @Transactional
    public TaskResponse addTask(Long requestId, CreateTaskRequest request) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findServiceRequestInTenant(requestId);
        guardNotClosed(sr);
        User currentUser = securityUtil.getCurrentUser();

        Task task = Task.builder()
            .title(request.getTitle())
            .description(request.getDescription())
            .priority(request.getPriority() != null
                ? request.getPriority() : ServiceRequestPriority.NORMAL)
            .dueDate(request.getDueDate())
            .slaDeadline(request.getSlaDeadline())
            .serviceRequest(sr)
            .company(companyRef(companyId))
            .createdBy(currentUser)
            .estimatedHours(request.getEstimatedHours())
            .build();

        if (request.getAssignedEmployeeId() != null) {
            Employee emp = employeeRepository
                .findByIdAndCompanyId(request.getAssignedEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Employee not found: " + request.getAssignedEmployeeId()));
            task.setAssignedEmployee(emp);
            if (emp.getUser() != null) {
                notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                    NotificationType.REQUEST_ASSIGNED,
                    "Task Assigned",
                    "A new task \"" + task.getTitle() + "\" has been assigned to you.",
                    emp.getUser().getId(), companyId, requestId
                ));
            }
        }

        if (request.getWorkflowStageId() != null) {
            task.setWorkflowStage(
                workflowStageRepository.findByIdAndCompanyId(
                    request.getWorkflowStageId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Workflow stage not found: " + request.getWorkflowStageId())));
        }

        taskRepository.save(task);
        return TaskMapper.toTaskResponse(task);
    }

    @Override
    @Transactional(readOnly = true)
    public List<TaskResponse> getTasks(Long requestId) {
        findServiceRequestInTenant(requestId);
        return taskRepository.findByServiceRequestIdOrderByCreatedAtAsc(requestId)
            .stream().map(TaskMapper::toTaskResponse).toList();
    }

    @Override
    @Transactional
    public TaskResponse updateTask(Long requestId, Long taskId, UpdateTaskRequest request) {
        Long companyId = requireCompanyId();
        ServiceRequest sr = findServiceRequestInTenant(requestId);
        guardNotClosed(sr);
        Task task = taskRepository.findByIdAndCompanyId(taskId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Task not found: " + taskId));

        if (request.getTitle()       != null) task.setTitle(request.getTitle());
        if (request.getDescription() != null) task.setDescription(request.getDescription());
        if (request.getPriority()    != null) task.setPriority(request.getPriority());
        if (request.getDueDate()     != null) task.setDueDate(request.getDueDate());
        if (request.getSlaDeadline() != null) task.setSlaDeadline(request.getSlaDeadline());
        if (request.getEstimatedHours() != null) task.setEstimatedHours(request.getEstimatedHours());
        if (request.getStatus()      != null) {
            task.setStatus(request.getStatus());
            if (request.getStatus() == TaskStatus.COMPLETED && task.getCompletedAt() == null)
                task.setCompletedAt(LocalDateTime.now());
        }
        if (request.getAssignedEmployeeId() != null) {
            Employee emp = employeeRepository.findByIdAndCompanyId(
                    request.getAssignedEmployeeId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException(
                        "Employee not found: " + request.getAssignedEmployeeId()));
            boolean reassigned = task.getAssignedEmployee() == null
                    || !task.getAssignedEmployee().getId().equals(emp.getId());
            task.setAssignedEmployee(emp);
            if (reassigned && emp.getUser() != null) {
                notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                    NotificationType.REQUEST_ASSIGNED,
                    "Task Assigned",
                    "Task \"" + task.getTitle() + "\" has been assigned to you.",
                    emp.getUser().getId(), companyId, requestId
                ));
            }
        }
        taskRepository.save(task);
        return TaskMapper.toTaskResponse(task);
    }

    @Override
    @Transactional
    public void deleteTask(Long requestId, Long taskId) {
        ServiceRequest sr = findServiceRequestInTenant(requestId);
        guardNotClosed(sr);
        Task task = taskRepository.findByIdAndCompanyId(taskId, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Task not found: " + taskId));
        task.softDelete();
    }

    private void guardNotClosed(ServiceRequest sr) {
        if (sr.isPermanentlyClosed())
            throw new BadRequestException("This request is permanently closed");
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

    private ServiceRequest findServiceRequestInTenant(Long id) {
        ServiceRequest sr = serviceRequestRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Service request not found: " + id));
        guardAccess(sr);
        return sr;
    }

    /** Staff have full tenant-scoped access; only CLIENT is restricted to requests they own. */
    private void guardAccess(ServiceRequest sr) {
        User user = securityUtil.getCurrentUser();
        if (user == null || user.getRole() == null) return;

        String role = user.getRole().name();
        if (!role.equals("CLIENT")) return;

        boolean isOwner = sr.getClient() != null
                && sr.getClient().getUser() != null
                && sr.getClient().getUser().getId().equals(user.getId());

        if (!isOwner) {
            throw new ForbiddenException("You do not have permission to access tasks for this service request");
        }
    }
}
