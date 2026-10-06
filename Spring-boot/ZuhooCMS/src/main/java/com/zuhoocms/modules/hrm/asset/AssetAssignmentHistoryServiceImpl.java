package com.zuhoocms.modules.hrm.asset;


import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AssetAssignmentHistoryServiceImpl implements AssetAssignmentHistoryService {

    private final AssetAssignmentHistoryRepository historyRepository;
    private final EmployeeRepository               employeeRepository;
    private final SecurityUtil                     securityUtil;
    private final AuthorizationService             authorizationService;

    // Per-asset history had no permission check: anyone in the company could read who held any device and when.
    @Transactional(readOnly = true)
    @Override
    public Page<AssetAssignmentHistoryResponse> historyForAsset(Long assetId, Pageable pageable) {
        requireHistoryView();
        Long companyId = requireCompanyId();
        return historyRepository.findByCompanyIdAndAssetIdOrderByAssignedAtDesc(companyId, assetId, pageable)
            .map(AssetAssignmentHistoryMapper::toAssetHistoryResponse);
    }

    /** An employee may always read their own assignment history; anyone else's needs a view permission. */
    @Transactional(readOnly = true)
    @Override
    public Page<AssetAssignmentHistoryResponse> historyForEmployee(Long employeeId, Pageable pageable) {
        if (!hasHistoryView()) {
            var user = securityUtil.getCurrentUser();
            Long myEmployeeId = user == null ? null
                : employeeRepository.findByUserId(user.getId()).map(Employee::getId).orElse(null);
            if (myEmployeeId == null || !myEmployeeId.equals(employeeId)) {
                throw new ForbiddenException("You can only view your own asset history");
            }
        }
        Long companyId = requireCompanyId();
        return historyRepository.findByCompanyIdAndEmployeeIdOrderByAssignedAtDesc(companyId, employeeId, pageable)
            .map(AssetAssignmentHistoryMapper::toAssetHistoryResponse);
    }

    // One endpoint backs both the ITAM Assignments page and the HRM asset history view, so either permission unlocks it.
    @Transactional(readOnly = true)
    @Override
    public Page<AssetAssignmentHistoryResponse> listAll(Pageable pageable) {
        authorizationService.checkAnyPermission(PermissionCode.ASSET_ASSIGNMENT_VIEW, PermissionCode.ASSET_VIEW);
        Long companyId = requireCompanyId();
        return historyRepository.findByCompanyIdOrderByAssignedAtDesc(companyId, pageable)
            .map(AssetAssignmentHistoryMapper::toAssetHistoryResponse);
    }

    private boolean hasHistoryView() {
        return authorizationService.hasPermission(PermissionCode.HARDWARE_VIEW)
            || authorizationService.hasPermission(PermissionCode.ASSET_VIEW)
            || authorizationService.hasPermission(PermissionCode.ASSET_ASSIGNMENT_VIEW);
    }

    private void requireHistoryView() {
        if (!hasHistoryView()) {
            throw new ForbiddenException("You don't have permission to view asset history");
        }
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
