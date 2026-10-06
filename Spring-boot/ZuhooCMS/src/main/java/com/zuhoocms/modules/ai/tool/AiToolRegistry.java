package com.zuhoocms.modules.ai.tool;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/**
 * Collects the AiTool beans and filters by the caller's permissions before the list reaches a provider, so an unauthorized tool is never even visible to the model.
 * Takes {@code ObjectProvider<List<AiTool>>} rather than the list directly: tools wrap services that depend on AiService, so an eager list forms a bean-creation cycle.
 */
@Component
@RequiredArgsConstructor
public class AiToolRegistry {

    private final ObjectProvider<List<AiTool>> toolsProvider;
    private final AuthorizationService authorizationService;

    public List<AiTool> all() {
        return toolsProvider.getObject();
    }

    /** Tools the current caller is actually allowed to invoke, right now. */
    public List<AiTool> availableForCurrentUser() {
        return all().stream()
            .filter(this::isAvailable)
            .toList();
    }

    public Optional<AiTool> byName(String name) {
        return all().stream().filter(t -> t.name().equals(name)).findFirst();
    }

    private boolean isAvailable(AiTool tool) {
        PermissionCode required = tool.requiredPermission();
        return required == null || authorizationService.hasPermission(required);
    }
}
