package com.zuhoocms.modules.support.message;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import com.zuhoocms.modules.support.SupportPaging;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/v1/support/messages")
@RequiredArgsConstructor
@Tag(name = "Support Messages", description = "Support Message Management")
public class SupportMessageController {

    private final SupportMessageService service;

    @PostMapping
    // SUPPORT_MANAGER is included: the role can read internal notes and delete messages, so without it a manager could open a conversation but not reply.
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Create Message")
    public ResponseEntity<SupportMessageResponse> create(@Valid @RequestBody SupportMessageRequest request) {
        return new ResponseEntity<>(service.create(request), HttpStatus.CREATED);
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Message by ID")
    public ResponseEntity<SupportMessageResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(service.getById(id));
    }

    @GetMapping("/ticket/{ticketId}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Messages by Ticket")
    public ResponseEntity<Page<SupportMessageResponse>> getByTicket(
            @PathVariable Long ticketId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getByTicket(ticketId, SupportPaging.of(page, size, Sort.by("createdAt").ascending())));
    }

    @GetMapping("/ticket/{ticketId}/external")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get External Messages by Ticket")
    public ResponseEntity<List<SupportMessageResponse>> getExternalMessages(@PathVariable Long ticketId) {
        return ResponseEntity.ok(service.getExternalMessages(ticketId));
    }

    @GetMapping("/ticket/{ticketId}/internal")
    @PreAuthorize("hasAnyRole('SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Internal Notes by Ticket")
    public ResponseEntity<List<SupportMessageResponse>> getInternalNotes(@PathVariable Long ticketId) {
        return ResponseEntity.ok(service.getInternalNotes(ticketId));
    }

    @PatchMapping("/{id}")
    // Author-only - enforced in the service.
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Update Message")
    public ResponseEntity<SupportMessageResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody SupportMessageRequest request) {
        return ResponseEntity.ok(service.update(id, request));
    }

    @DeleteMapping("/{id}")
    // Author, platform manager/admin, or the owning COMPANY_OWNER - enforced in the service.
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Delete Message")
    public ResponseEntity<SupportMessageResponse> delete(@PathVariable Long id) {
        return ResponseEntity.ok(service.delete(id));
    }

    // Client-facing: messages on the client's own CUSTOMER_SUPPORT ticket, ownership-checked in the service and always external (isInternal forced false).

    @PostMapping("/client")
    @PreAuthorize("hasRole('CLIENT')")
    @Operation(summary = "[Client] Create Message")
    public ResponseEntity<SupportMessageResponse> createForClient(@Valid @RequestBody SupportMessageRequest request) {
        return new ResponseEntity<>(service.createForClient(request), HttpStatus.CREATED);
    }

    @GetMapping("/client/ticket/{ticketId}")
    @PreAuthorize("hasRole('CLIENT')")
    @Operation(summary = "[Client] Get Messages on My Ticket")
    public ResponseEntity<List<SupportMessageResponse>> getClientMessages(@PathVariable Long ticketId) {
        return ResponseEntity.ok(service.getClientMessages(ticketId));
    }
}
