package com.zuhoocms.modules.hrm.asset;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.hrm.employee.Employee;

import com.zuhoocms.modules.itam.shared.AssetHistory;

public class AssetAssignmentHistoryMapper {

    public static AssetAssignmentHistoryResponse toAssetHistoryResponse(AssetHistory h) {
        Asset asset = h.getAsset();
        Employee emp = h.getEmployee();
        User empUser = emp != null ? emp.getUser() : null;
        User assignedBy = h.getAssignedBy();
        AssetAssignmentHistoryResponse r = new AssetAssignmentHistoryResponse();
        r.setId(h.getId());
        r.setAssetId(asset != null ? asset.getId() : null);
        r.setAssetName(asset != null ? asset.getName() : null);
        r.setEmployeeId(emp != null ? emp.getId() : null);
        r.setEmployeeName(empUser != null ? empUser.getFullName() : null);
        r.setAssignedAt(h.getAssignedAt());
        r.setReturnedAt(h.getReturnedAt());
        r.setCondition(h.getCondition());
        r.setConditionOnReturn(h.getConditionOnReturn());
        r.setNotes(h.getNotes());
        r.setAssignedById(assignedBy != null ? assignedBy.getId() : null);
        r.setAssignedByName(assignedBy != null ? assignedBy.getFullName() : null);
        r.setCreatedAt(h.getCreatedAt());
        return r;
    }
}
