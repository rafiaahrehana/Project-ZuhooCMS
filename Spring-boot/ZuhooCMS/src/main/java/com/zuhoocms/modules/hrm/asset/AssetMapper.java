package com.zuhoocms.modules.hrm.asset;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.hrm.employee.Employee;

public class AssetMapper {

    /** A terminated employee's lazy proxy throws on any field access beyond its id - see TimesheetMapper.safeUser. */
    private static User safeUser(Employee emp) {
        if (emp == null) return null;
        try {
            return emp.getUser();
        } catch (Exception e) {
            return null;
        }
    }

    public static AssetResponse toAssetResponse(Asset a) {
        Employee assigned = a.getAssignedTo();
        User assignedUser = safeUser(assigned);
        AssetResponse r = new AssetResponse();
        r.setId(a.getId());
        r.setName(a.getName());
        r.setCategory(a.getCategory());
        r.setSerialNumber(a.getSerialNumber());
        // description and notes are ONE column, echoed under two names. The web had an input box for each, so a
        // client sending both had notes silently overwrite description on update (they are applied in that order to
        // the same setter) - editing the Description box stored the old text and answered 200. Both front-ends now
        // show a single box. Left as two keys on the wire because clients bind to both; the aliasing is written down
        // here so the next reader does not take them for two fields.
        r.setDescription(a.getNotes());
        r.setPurchaseDate(a.getPurchaseDate());
        r.setPurchaseCost(a.getPurchasePrice());
        r.setStatus(a.getStatus());
        r.setAssignedAt(a.getAssignedAt());
        r.setReturnDate(a.getReturnedAt());
        r.setNotes(a.getNotes());
        r.setAssignedToId(assigned != null ? assigned.getId() : null);
        r.setAssignedToName(assignedUser != null ? assignedUser.getFullName() : null);
        r.setCreatedAt(a.getCreatedAt());
        r.setAssetTag(a.getAssetTag());
        r.setBrand(a.getBrand());
        r.setModel(a.getModel());
        r.setIpAddress(a.getIpAddress());
        r.setMacAddress(a.getMacAddress());
        r.setProcessorModel(a.getProcessorModel());
        r.setRamSize(a.getRamSize());
        r.setStorageSize(a.getStorageSize());
        r.setOperatingSystem(a.getOperatingSystem());
        r.setWarrantyExpiry(a.getWarrantyExpiry());
        r.setDisposalDate(a.getDisposalDate());
        r.setDisposalReason(a.getDisposalReason());
        return r;
    }
}
