package com.zuhoocms.modules.support.contextswitch;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Sort;
import com.zuhoocms.modules.support.SupportPaging;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.beans.factory.annotation.Value;

@RestController
@RequestMapping("/api/support/context-switches")
@RequiredArgsConstructor
@Tag(name = "Support Context Switches", description = "Support Agent Context Switch Management")
public class SupportContextSwitchController {

    private final SupportContextSwitchService service;

    @PostMapping("/switch")
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT')")
    @Operation(summary = "Switch Context to a Company")
    public ResponseEntity<SupportContextSwitchResponse> switchContext(
            @Valid @RequestBody SupportContextSwitchRequest request, HttpServletRequest httpRequest) {
        return ResponseEntity.ok(service.switchContext(request, resolveClientIp(httpRequest), httpRequest.getHeader("User-Agent")));
    }

    /** Comma-separated IPs of proxies whose X-Forwarded-For may be trusted; empty by default, since any client can send an arbitrary X-Forwarded-For. */
    @Value("${app.security.trusted-proxies:}")
    private String trustedProxiesConfig;

    /** X-Forwarded-For is consulted only when the direct peer is a trusted proxy; the chain is walked from the right and the first untrusted hop is the client. */
    String resolveClientIp(HttpServletRequest request) {
        String remote = request.getRemoteAddr();
        Set<String> trusted = trustedProxies();
        if (trusted.isEmpty() || !trusted.contains(remote)) {
            return remote;
        }
        String xff = request.getHeader("X-Forwarded-For");
        if (xff == null || xff.isBlank()) {
            return remote;
        }
        String[] hops = xff.split(",");
        for (int i = hops.length - 1; i >= 0; i--) {
            String hop = hops[i].trim();
            if (!hop.isEmpty() && !trusted.contains(hop)) {
                return hop;
            }
        }
        return remote;
    }

    private Set<String> trustedProxies() {
        if (trustedProxiesConfig == null || trustedProxiesConfig.isBlank()) {
            return Set.of();
        }
        return Arrays.stream(trustedProxiesConfig.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toSet());
    }

    @PostMapping("/{id}/end")
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT')")
    @Operation(summary = "End Context Switch")
    public ResponseEntity<Void> endContextSwitch(@PathVariable Long id) {
        service.endContextSwitch(id);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/active/agent/{supportAgentId}")
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT')")
    @Operation(summary = "Get Active Context Switch for an Agent")
    public ResponseEntity<SupportContextSwitchResponse> getActiveContextSwitch(@PathVariable Long supportAgentId) {
        return ResponseEntity.ok(service.getActiveContextSwitch(supportAgentId));
    }

    @GetMapping("/history/agent/{supportAgentId}")
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER')")
    @Operation(summary = "Get Context Switch History for an Agent")
    public ResponseEntity<Page<SupportContextSwitchResponse>> getContextSwitchHistory(
            @PathVariable Long supportAgentId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getContextSwitchHistory(supportAgentId, SupportPaging.of(page, size, Sort.by("switchedInTime").descending())));
    }

    @GetMapping("/active")
    // SUPPORT_AGENT is included or the Context Switches screen 403s for them; the service still returns only their own.
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT')")
    @Operation(summary = "Get All Active Context Switches")
    public ResponseEntity<List<SupportContextSwitchResponse>> getActiveContextSwitches() {
        return ResponseEntity.ok(service.getActiveContextSwitches());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('SUPER_ADMIN') or hasRole('SUPPORT_MANAGER')")
    @Operation(summary = "Get Context Switch by ID")
    public ResponseEntity<SupportContextSwitchResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(service.getById(id));
    }
}
