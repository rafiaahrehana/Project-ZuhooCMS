package com.zuhoocms.modules.hrm.leave;

import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceResponse;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestDto;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestResponse;
import com.zuhoocms.enums.LeaveRequestStatus;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;

import java.util.List;

import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.shared.exception.ForbiddenException;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/hr/leaves")
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class LeaveController {

    private final LeaveService leaveService;
    private final AuthorizationService authorizationService;
    private final SecurityUtil securityUtil;
    private final EmployeeRepository employeeRepository;

    @PostMapping
    public ResponseEntity<LeaveRequestResponse> apply(@Valid @RequestBody LeaveRequestDto request) {
        authorizationService.checkPermission(PermissionCode.LEAVE_CREATE);
        return new ResponseEntity<>(leaveService.apply(request), HttpStatus.CREATED);
    }

    @GetMapping
    public ResponseEntity<Page<LeaveRequestResponse>> listAll(
            @RequestParam(required = false) LeaveRequestStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        authorizationService.checkPermission(PermissionCode.LEAVE_VIEW);
        return ResponseEntity.ok(leaveService.listAll(status,
                PageRequest.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/my")
    public ResponseEntity<Page<LeaveRequestResponse>> listMine(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(leaveService.listMyLeaves(
                PageRequest.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/{id}")
    public ResponseEntity<LeaveRequestResponse> getById(@PathVariable Long id) {
        LeaveRequestResponse res = leaveService.getById(id);
        
        if (!authorizationService.hasPermission(PermissionCode.LEAVE_VIEW)) {
            com.zuhoocms.auth.user.User currentUser = securityUtil.getCurrentUser();
            if (currentUser == null) {
                throw new ForbiddenException("Access denied");
            }
            Employee currentEmp = employeeRepository.findByUserId(currentUser.getId()).orElse(null);
            if (currentEmp == null || !currentEmp.getId().equals(res.getEmployeeId())) {
                throw new ForbiddenException("Access denied: You can only view your own leave requests");
            }
        }
        
        return ResponseEntity.ok(res);
    }

    @PatchMapping("/{id}/review")
    public ResponseEntity<LeaveRequestResponse> review(
            @PathVariable Long id,
            @Valid @RequestBody ReviewLeaveRequest request) {
        authorizationService.checkPermission(PermissionCode.LEAVE_APPROVE);
        return ResponseEntity.ok(leaveService.review(id, request));
    }

    @PatchMapping("/{id}/cancel")
    public ResponseEntity<String> cancel(@PathVariable Long id) {
        LeaveRequestResponse res = leaveService.getById(id);
        
        if (!authorizationService.hasPermission(PermissionCode.LEAVE_CANCEL)) {
            com.zuhoocms.auth.user.User currentUser = securityUtil.getCurrentUser();
            if (currentUser == null) {
                throw new ForbiddenException("Access denied");
            }
            Employee currentEmp = employeeRepository.findByUserId(currentUser.getId()).orElse(null);
            if (currentEmp == null || !currentEmp.getId().equals(res.getEmployeeId())) {
                throw new ForbiddenException("Access denied: You can only cancel your own leave requests");
            }
        }

        leaveService.cancel(id);
        return ResponseEntity.ok("Leave requeststatus cancelled");
    }

    @GetMapping("/balances/my")
    public ResponseEntity<List<LeaveBalanceResponse>> getMyBalances(
            @RequestParam(defaultValue = "#{T(java.time.LocalDate).now().getYear()}") int year) {
        return ResponseEntity.ok(leaveService.getMyBalances(year));
    }

    @GetMapping("/balances/employee/{employeeId}")
    public ResponseEntity<List<LeaveBalanceResponse>> getBalancesForEmployee(
            @PathVariable Long employeeId,
            @RequestParam(defaultValue = "#{T(java.time.LocalDate).now().getYear()}") int year) {
        authorizationService.checkPermission(PermissionCode.LEAVE_VIEW);
        return ResponseEntity.ok(leaveService.getBalancesForEmployee(employeeId, year));
    }
}


