package com.zuhoocms.auth.role.service;

import com.zuhoocms.auth.role.enums.PermissionCode;

import java.util.List;

public interface AuthorizationService {

    void checkPermission(PermissionCode permission);

    /** Passes if the caller holds ANY one of the given permissions - for endpoints shared by two features. */
    void checkAnyPermission(PermissionCode... permissions);

    boolean hasPermission(PermissionCode permission);

    /** Same resolution rules as hasPermission(), enumerated rather than checked one at a time, to drive frontend permission-based UI. */
    List<String> getMyPermissionCodes();
}