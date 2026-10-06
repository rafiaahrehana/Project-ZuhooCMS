package com.zuhoocms.modules.servicedesk.approval;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.ApprovalStatus;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStage;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class StageApprovalServiceImpl implements StageApprovalService {

    private final StageApprovalRepository approvalRepository;
    private final ServiceRequestRepository requestRepository;
    private final ServiceRequestService requestService;
    private final NotificationService notificationService;
    private final SecurityUtil securityUtil;
    private final WorkflowStageRepository workflowStageRepository;
    private final EmployeeRepository employeeRepository;
    private final PlatformTransactionManager transactionManager;

    @Override
    @Transactional(readOnly = true)
    public Page<StageApprovalResponse> getPending(Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        return approvalRepository.findByCompanyIdAndStatus(companyId, ApprovalStatus.PENDING, pageable)
                .map(StageApprovalMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<StageApprovalResponse> getForRequest(Long serviceRequestId) {
        Long companyId = securityUtil.getCurrentCompanyId();
        ServiceRequest sr = requestRepository.findByIdAndCompanyId(serviceRequestId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service request not found"));

        // CLIENT may call this endpoint, and tenant scoping is shared by every client in the company, so without this one client could read another's approval trail by guessing an id. Mirrors ServiceRequestServiceImpl.guardAccess().
        User currentUser = securityUtil.getCurrentUser();
        if (currentUser != null && currentUser.getRole() == Role.CLIENT) {
            boolean isOwner = sr.getClient() != null
                    && sr.getClient().getUser() != null
                    && sr.getClient().getUser().getId().equals(currentUser.getId());
            if (!isOwner) {
                throw new ForbiddenException("You do not have permission to access this service request");
            }
        }

        return approvalRepository.findByServiceRequestId(sr.getId()).stream()
                .map(StageApprovalMapper::toResponse)
                .collect(Collectors.toList());
    }

    // Deliberately not @Transactional: with the decision and the stage advance in one transaction, a failure while advancing rolled the decision back and the item reappeared as PENDING.
    @Override
    public StageApprovalResponse approve(Long id, DecisionRequest request) {
        TransactionTemplate tx = new TransactionTemplate(transactionManager);
        StageApprovalResponse recorded = tx.execute(status -> {
            StageApproval approval = getPendingApprovalInTenant(id);
            requireAssignedApprover(approval);

            ServiceRequest sr = approval.getServiceRequest();
            if (sr.isPermanentlyClosed()) {
                throw new BadRequestException("This request is permanently closed");
            }
            requireCurrentStage(approval, sr);

            User currentUser = securityUtil.getCurrentUser();
            String selfApprovalNote = checkSelfApproval(approval, currentUser);

            approval.setStatus(ApprovalStatus.APPROVED);
            approval.setDecisionNotes(selfApprovalNote == null
                ? request.getDecisionNotes()
                : selfApprovalNote + (request.getDecisionNotes() != null ? " " + request.getDecisionNotes() : ""));
            approval.setDecidedAt(LocalDateTime.now());
            approval.setDecidedBy(currentUser);

            approvalRepository.save(approval);
            return StageApprovalMapper.toResponse(approval);
        });

        // A failure here must not undo the recorded decision; staff can retry via POST /advance-stage, which sees the APPROVED row and proceeds.
        try {
            requestService.advanceStage(recorded.getServiceRequestId());
        } catch (Exception ex) {
            log.warn("Approval {} recorded, but advancing request {} failed: {}",
                id, recorded.getServiceRequestId(), ex.getMessage());
        }

        return recorded;
    }

    /** Approving a row for any stage other than the one the request is on (stale row, or it moved on) used to silently advance the wrong stage. */
    private void requireCurrentStage(StageApproval approval, ServiceRequest sr) {
        if (sr.getCompanyService() == null || sr.getCompanyService().getWorkflowTemplate() == null) {
            throw new BadRequestException("This request's service no longer has a workflow template");
        }
        List<WorkflowStage> stages = workflowStageRepository
            .findByWorkflowTemplateIdOrderByStageOrderAsc(sr.getCompanyService().getWorkflowTemplate().getId());
        int current = sr.getCurrentStage() != null ? sr.getCurrentStage() : 0;
        WorkflowStage currentStage = current < stages.size() ? stages.get(current) : null;
        if (currentStage == null || !currentStage.getId().equals(approval.getWorkflowStage().getId())) {
            throw new BadRequestException("This approval is for stage \"" + approval.getWorkflowStage().getName()
                + "\", but the request is currently "
                + (currentStage == null ? "past its final stage" : "at stage \"" + currentStage.getName() + "\"")
                + " - it can no longer be approved");
        }
    }

    /** Four-eyes rule: the requester may not approve, except the company owner when no one else is eligible - returns a note to prefix so the audit trail shows the self-approval. */
    private String checkSelfApproval(StageApproval approval, User currentUser) {
        User requester = approval.getRequestedBy();
        if (requester == null || currentUser == null || !requester.getId().equals(currentUser.getId())) {
            return null;
        }
        if (currentUser.getRole() == Role.COMPANY_OWNER
                && !hasOtherEligibleApprover(approval, currentUser)) {
            return "[Self-approved by company owner - no other eligible approver]";
        }
        throw new ForbiddenException("You requested this approval yourself - another eligible approver must decide it");
    }

    private boolean hasOtherEligibleApprover(StageApproval approval, User currentUser) {
        String requiredRole = approval.getApproverRole();
        for (Employee employee : employeeRepository.findByCompanyIdAndActiveTrue(approval.getCompany().getId())) {
            User u = employee.getUser();
            if (u == null || u.getId().equals(currentUser.getId()) || u.getRole() == Role.CLIENT) continue;
            if (u.getRole() == Role.COMPANY_OWNER) return true;
            if (requiredRole == null || requiredRole.isBlank()) return true;
            if (u.getCustomRole() != null && requiredRole.equalsIgnoreCase(u.getCustomRole().getName())) return true;
        }
        return false;
    }

    @Override
    @Transactional
    public StageApprovalResponse reject(Long id, DecisionRequest request) {
        StageApproval approval = getPendingApprovalInTenant(id);
        requireAssignedApprover(approval);

        approval.setStatus(ApprovalStatus.REJECTED);
        approval.setDecisionNotes(request.getDecisionNotes());
        approval.setDecidedAt(LocalDateTime.now());
        approval.setDecidedBy(securityUtil.getCurrentUser());

        approvalRepository.save(approval);

        if (approval.getRequestedBy() != null) {
            ServiceRequest sr = approval.getServiceRequest();
            notificationService.sendForServiceRequest(CreateNotificationRequest.forRequest(
                NotificationType.REQUEST_UPDATED,
                "Stage Approval Rejected",
                "The approval for stage \"" + approval.getWorkflowStage().getName()
                    + "\" on request \"" + sr.getTitle() + "\" was rejected.",
                approval.getRequestedBy().getId(), approval.getCompany().getId(), sr.getId()
            ));
        }

        return StageApprovalMapper.toResponse(approval);
    }

    // The controller's hasAnyRole('COMPANY_OWNER','EMPLOYEE') would let any employee decide any stage, so enforce StageApproval.approverRole here.
    // COMPANY_OWNER can always decide; a stage with no approverRole stays open to any EMPLOYEE.
    private void requireAssignedApprover(StageApproval approval) {
        User user = securityUtil.getCurrentUser();
        if (user == null) {
            throw new ForbiddenException("You do not have permission to decide this approval");
        }
        if (user.getRole() == Role.COMPANY_OWNER) {
            return;
        }

        String requiredRole = approval.getApproverRole();
        if (requiredRole == null || requiredRole.isBlank()) {
            return;
        }

        String actualRole = user.getCustomRole() != null ? user.getCustomRole().getName() : null;
        if (actualRole == null || !actualRole.equalsIgnoreCase(requiredRole)) {
            throw new ForbiddenException(
                    "This approval is assigned to the \"" + requiredRole + "\" role - you are not authorized to decide it");
        }
    }

    private StageApproval getPendingApprovalInTenant(Long id) {
        Long companyId = securityUtil.getCurrentCompanyId();
        StageApproval approval = approvalRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Approval request not found"));

        if (approval.getStatus() != ApprovalStatus.PENDING) {
            throw new BadRequestException("Approval request is already decided");
        }

        return approval;
    }
}
