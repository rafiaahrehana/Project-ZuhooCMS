package com.zuhoocms.auth.role.config;

import com.zuhoocms.auth.role.service.PermissionService;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class PermissionInitializer implements CommandLineRunner {

    private final PermissionService permissionService;

    @Override
    public void run(String... args) {
        permissionService.initializePermissions();
    }
}
