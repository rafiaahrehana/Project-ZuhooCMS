package com.zuhoocms.modules.hrm.asset;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.enums.AssetStatus;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;

import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor

public class AssetServiceImpl implements AssetService {

    private final AssetRepository assetRepository;
    private final EmployeeRepository employeeRepository;
    private final AssetAssignmentHistoryRepository historyRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final NotificationService notificationService;
    private final com.zuhoocms.modules.itam.shared.ItamEmployeeGuard employeeGuard;

    @Override
    @Transactional
    public AssetResponse create(AssetRequest request) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_CREATE);
        Long companyId = requireCompanyId();
        // The CSV importer already checks this; manual entry through this form never did.
        if (request.getSerialNumber() != null && !request.getSerialNumber().isBlank()
                && assetRepository.existsByCompanyIdAndSerialNumber(companyId, request.getSerialNumber())) {
            throw new BadRequestException("An asset with this serial number already exists");
        }
        if (request.getAssetTag() != null && !request.getAssetTag().isBlank()
                && assetRepository.existsByCompanyIdAndAssetTag(companyId, request.getAssetTag())) {
            throw new BadRequestException("An asset with this asset tag already exists");
        }
        Asset asset = new Asset(); asset.setName(request.getName()); asset.setCategory(request.getCategory()); asset.setSerialNumber(request.getSerialNumber()); asset.setNotes(request.getDescription() != null ? request.getDescription() : request.getNotes()); asset.setPurchaseDate(request.getPurchaseDate()); asset.setPurchasePrice(request.getPurchaseCost()); asset.setStatus(AssetStatus.AVAILABLE); asset.setCompany(companyRef(companyId));
        asset.setAssetTag(request.getAssetTag());
        asset.setBrand(request.getBrand());
        asset.setModel(request.getModel());
        asset.setIpAddress(request.getIpAddress());
        asset.setMacAddress(request.getMacAddress());
        asset.setProcessorModel(request.getProcessorModel());
        asset.setRamSize(request.getRamSize());
        asset.setStorageSize(request.getStorageSize());
        asset.setOperatingSystem(request.getOperatingSystem());
        asset.setWarrantyExpiry(request.getWarrantyExpiry());

        if (request.getAssignedToId() != null) {
            Employee emp = findEmployee(request.getAssignedToId(), companyId);
            asset.setAssignedTo(emp);
            asset.setStatus(AssetStatus.ASSIGNED);
            asset.setAssignedAt(LocalDate.now());
            assetRepository.save(asset);
            recordHistory(asset, emp, LocalDate.now(), null, null, companyId);
            notifyAssigned(asset, emp, companyId);
        } else {
            assetRepository.save(asset);
        }
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional(readOnly = true)
    public AssetResponse getById(Long id) {
        Asset asset = findInTenant(id);
        requireViewOrOwn(asset.getAssignedTo() != null ? asset.getAssignedTo().getId() : null);
        return AssetMapper.toAssetResponse(asset);
    }

    // One endpoint backs both the ITAM Hardware admin page and the HRM Assets page, so either permission unlocks it.
    @Override
    @Transactional(readOnly = true)
    public Page<AssetResponse> listAll(AssetStatus status, Pageable pageable) {
        authorizationService.checkAnyPermission(PermissionCode.HARDWARE_VIEW, PermissionCode.ASSET_VIEW);
        Long companyId = requireCompanyId();
        Page<Asset> page = status != null
            ? assetRepository.findByCompanyIdAndStatus(companyId, status, pageable)
            : assetRepository.findByCompanyId(companyId, pageable);
        return page.map(AssetMapper::toAssetResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AssetResponse> listForEmployee(Long employeeId) {
        requireViewOrOwn(employeeId);
        return assetRepository.findByCompanyIdAndAssignedToId(requireCompanyId(), employeeId)
            .stream().map(AssetMapper::toAssetResponse).toList();
    }

    @Override
    @Transactional
    public AssetResponse update(Long id, AssetRequest request) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_UPDATE);
        Long companyId = requireCompanyId();
        Asset asset = findInTenant(id);
        if (request.getSerialNumber() != null && !request.getSerialNumber().isBlank()
                && !request.getSerialNumber().equals(asset.getSerialNumber())
                && assetRepository.existsByCompanyIdAndSerialNumber(companyId, request.getSerialNumber())) {
            throw new BadRequestException("An asset with this serial number already exists");
        }
        if (request.getAssetTag() != null && !request.getAssetTag().isBlank()
                && !request.getAssetTag().equals(asset.getAssetTag())
                && assetRepository.existsByCompanyIdAndAssetTag(companyId, request.getAssetTag())) {
            throw new BadRequestException("An asset with this asset tag already exists");
        }
        if (request.getName()         != null) asset.setName(request.getName());
        if (request.getCategory()     != null) asset.setCategory(request.getCategory());
        if (request.getSerialNumber() != null) asset.setSerialNumber(request.getSerialNumber());
        if (request.getDescription()  != null) asset.setNotes(request.getDescription());
        if (request.getPurchaseDate() != null) asset.setPurchaseDate(request.getPurchaseDate());
        if (request.getPurchaseCost() != null) asset.setPurchasePrice(request.getPurchaseCost());
        if (request.getNotes()        != null) asset.setNotes(request.getNotes());
        if (request.getAssetTag()        != null) asset.setAssetTag(request.getAssetTag());
        if (request.getBrand()           != null) asset.setBrand(request.getBrand());
        if (request.getModel()           != null) asset.setModel(request.getModel());
        if (request.getIpAddress()       != null) asset.setIpAddress(request.getIpAddress());
        if (request.getMacAddress()      != null) asset.setMacAddress(request.getMacAddress());
        if (request.getProcessorModel()  != null) asset.setProcessorModel(request.getProcessorModel());
        if (request.getRamSize()         != null) asset.setRamSize(request.getRamSize());
        if (request.getStorageSize()     != null) asset.setStorageSize(request.getStorageSize());
        if (request.getOperatingSystem() != null) asset.setOperatingSystem(request.getOperatingSystem());
        if (request.getWarrantyExpiry()  != null && !request.getWarrantyExpiry().equals(asset.getWarrantyExpiry())) {
            asset.setWarrantyExpiry(request.getWarrantyExpiry());
            // A new warranty date is a new warranty, so WarrantyExpiryScheduler must be free to alert on it again.
            asset.setWarrantyExpiringSoonAlertedAt(null);
            asset.setWarrantyExpiredAlertedAt(null);
        }
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional
    public AssetResponse assign(Long id, Long employeeId) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_UPDATE);
        Long companyId = requireCompanyId();
        // Locked read-then-write: concurrent assigns raced, silently losing one assignment and leaving an orphaned open history row. Matches SoftwareLicenseServiceImpl.assignSeat().
        Asset asset = assetRepository.findByIdAndCompanyIdForUpdate(id, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Asset not found: " + id));
        if (asset.getStatus() != AssetStatus.AVAILABLE) {
            throw new BadRequestException(asset.getStatus() == AssetStatus.ASSIGNED
                ? "Asset is already assigned. Unassign it first."
                : "Only an available asset can be assigned (current status: " + asset.getStatus() + ")");
        }
        Employee emp = findEmployee(employeeId, companyId);
        asset.setAssignedTo(emp);
        asset.setStatus(AssetStatus.ASSIGNED);
        asset.setAssignedAt(LocalDate.now());
        asset.setReturnedAt(null);
        recordHistory(asset, emp, LocalDate.now(), null, null, companyId);
        notifyAssigned(asset, emp, companyId);
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional
    public AssetResponse setMaintenance(Long id, boolean underMaintenance) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_UPDATE);
        Asset asset = lockInTenant(id);
        if (asset.getStatus() == AssetStatus.ASSIGNED) {
            throw new BadRequestException("Cannot change maintenance status on an assigned asset. Unassign it first.");
        }
        if (asset.getStatus() == AssetStatus.DISPOSED) {
            throw new BadRequestException("This asset has been disposed and can no longer be modified.");
        }
        if (underMaintenance) {
            if (asset.getStatus() != AssetStatus.AVAILABLE) {
                throw new BadRequestException("Asset is already under maintenance");
            }
            asset.setStatus(AssetStatus.UNDER_MAINTENANCE);
        } else {
            if (asset.getStatus() != AssetStatus.UNDER_MAINTENANCE) {
                throw new BadRequestException("Asset is not currently under maintenance");
            }
            asset.setStatus(AssetStatus.AVAILABLE);
        }
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional
    public AssetResponse dispose(Long id, String reason) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_UPDATE);
        // Same row lock as assign(): an assign racing a dispose could hand out an asset in the instant it is written off.
        Asset asset = lockInTenant(id);
        if (asset.getStatus() == AssetStatus.ASSIGNED) {
            throw new BadRequestException("Cannot dispose an assigned asset. Unassign it first.");
        }
        if (asset.getStatus() == AssetStatus.DISPOSED) {
            throw new BadRequestException("This asset has already been disposed");
        }
        asset.setStatus(AssetStatus.DISPOSED);
        asset.setDisposalDate(LocalDate.now());
        asset.setDisposalReason(reason);
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional
    public AssetResponse unassign(Long id) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_UPDATE);
        Long companyId = requireCompanyId();
        Asset asset = lockInTenant(id);
        if (asset.getStatus() != AssetStatus.ASSIGNED) {
            throw new BadRequestException("Asset is not currently assigned");
        }
        historyRepository.findTopByAssetIdAndCompanyIdAndReturnedAtIsNullOrderByAssignedAtDesc(id, companyId)
            .ifPresent(h -> {
                h.setReturnedAt(LocalDate.now());
                historyRepository.save(h);
            });
        asset.setAssignedTo(null);
        asset.setStatus(AssetStatus.AVAILABLE);
        asset.setReturnedAt(LocalDate.now());
        return AssetMapper.toAssetResponse(asset);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.HARDWARE_DELETE);
        Asset asset = findInTenant(id);
        if (asset.getStatus() == AssetStatus.ASSIGNED) {
            throw new BadRequestException("Cannot delete an assigned asset. Unassign it first.");
        }
        asset.softDelete();
    }

    // Without this an employee only learns of an assigned asset by checking "My Assets".
    private void notifyAssigned(Asset asset, Employee emp, Long companyId) {
        if (emp.getUser() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.ASSET_ASSIGNED,
                "Asset assigned to you",
                asset.getName() + (asset.getAssetTag() != null ? " (" + asset.getAssetTag() + ")" : "") + " has been assigned to you",
                "/itam/hardware",
                emp.getUser().getId(),
                companyId));
    }

    private void recordHistory(Asset asset, Employee emp, LocalDate assignedAt,
                                LocalDate returnedAt, String condition, Long companyId) {
        Company c = new Company(); c.setId(companyId);
        com.zuhoocms.modules.itam.shared.AssetHistory history = com.zuhoocms.modules.itam.shared.AssetHistory.builder()
            .asset(asset)
            .employee(emp)
            .company(c)
            .assignedAt(assignedAt)
            .returnedAt(returnedAt)
            .condition(condition)
            .assignedBy(securityUtil.getCurrentUser())
            .build();
        historyRepository.save(history);
    }

    private Asset lockInTenant(Long id) {
        return assetRepository.findByIdAndCompanyIdForUpdate(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Asset not found: " + id));
    }

    /** Reading an asset needed no permission at all; HARDWARE_VIEW (ITAM) or ASSET_VIEW (HRM) unlock any employee, everyone else sees only their own. */
    private void requireViewOrOwn(Long assignedEmployeeId) {
        if (authorizationService.hasPermission(PermissionCode.HARDWARE_VIEW)
                || authorizationService.hasPermission(PermissionCode.ASSET_VIEW)) {
            return;
        }
        var user = securityUtil.getCurrentUser();
        Long myEmployeeId = user == null ? null
            : employeeRepository.findByUserId(user.getId()).map(Employee::getId).orElse(null);
        if (myEmployeeId == null || assignedEmployeeId == null || !myEmployeeId.equals(assignedEmployeeId)) {
            throw new ForbiddenException("You can only view assets assigned to you");
        }
    }

    private Asset findInTenant(Long id) {
        return assetRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Asset not found: " + id));
    }

    /** Locks the employee row and rejects (400) an inactive/terminated employee or one with an open offboarding checklist, as licence seats do, serialised against offboarding completion. */
    private Employee findEmployee(Long employeeId, Long companyId) {
        employeeGuard.requireAssignable(employeeId, companyId);
        return employeeRepository.findByIdAndCompanyId(employeeId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));
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

