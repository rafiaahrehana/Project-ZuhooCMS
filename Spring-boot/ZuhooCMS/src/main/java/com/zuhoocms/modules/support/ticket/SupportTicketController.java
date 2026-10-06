package com.zuhoocms.modules.support.ticket;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import com.zuhoocms.modules.support.SupportPaging;
import com.zuhoocms.modules.support.message.ClientTicketReplyRequest;
import com.zuhoocms.modules.support.message.SupportMessageResponse;
import com.zuhoocms.modules.support.message.SupportMessageService;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/support/tickets")
@RequiredArgsConstructor
@Tag(name = "Support Tickets", description = "Support Ticket Management")
public class SupportTicketController {

    private final SupportTicketService service;
    private final SupportMessageService messageService;

    @PostMapping
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "Create Support Ticket")
    public ResponseEntity<SupportTicketResponse> create(@Valid @RequestBody SupportTicketRequest request) {
        return new ResponseEntity<>(service.create(request), HttpStatus.CREATED);
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Ticket by ID")
    public ResponseEntity<SupportTicketResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(service.getById(id));
    }

    @GetMapping("/number/{number}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'SUPPORT_AGENT', 'SUPPORT_MANAGER', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Ticket by Number")
    public ResponseEntity<SupportTicketResponse> getByNumber(@PathVariable String number) {
        return ResponseEntity.ok(service.getByTicketNumber(number));
    }

    @GetMapping
    @PreAuthorize("hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get all Tickets")
    public ResponseEntity<Page<SupportTicketResponse>> getAll(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getAll(SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/my-tickets")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "Get My Tickets")
    public ResponseEntity<Page<SupportTicketResponse>> getMyTickets(
            @RequestParam(required = false) Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getMyTickets(userId, SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/assigned-to-me")
    @PreAuthorize("hasRole('SUPPORT_AGENT')")
    @Operation(summary = "Get Tickets Assigned to Me")
    public ResponseEntity<Page<SupportTicketResponse>> getAssignedToMe(
            // Ignored, kept only so existing clients that still send it keep working; the caller's own agent record is used.
            @RequestParam(required = false) Long agentId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getAssignedToMe(SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/status/{status}")
    @PreAuthorize("hasRole('SUPPORT_AGENT') or hasRole('SUPPORT_MANAGER') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Tickets by Status")
    public ResponseEntity<Page<SupportTicketResponse>> getByStatus(
            @PathVariable TicketStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getByStatus(status, SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/sla-breached")
    @PreAuthorize("hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get SLA Breached Tickets")
    public ResponseEntity<?> getSLABreached() {
        return ResponseEntity.ok(service.getSLABreachedTickets());
    }

    @GetMapping("/critical-open")
    @PreAuthorize("hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Get Critical Open Tickets")
    public ResponseEntity<?> getCriticalOpen() {
        return ResponseEntity.ok(service.getOpenCriticalTickets());
    }

    // Platform support staff only: a COMPANY_OWNER (or an admin impersonating one) must not route work to platform agents. Same for reassign below.
    @PostMapping("/{id}/assign")
    @PreAuthorize("hasAnyRole('SUPPORT_MANAGER', 'SUPPORT_AGENT', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Assign Ticket to Agent")
    public ResponseEntity<Void> assign(
            @PathVariable Long id,
            @RequestParam Long agentId) {
        service.assignToAgent(id, agentId);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/reassign")
    @PreAuthorize("hasAnyRole('SUPPORT_MANAGER', 'SUPPORT_AGENT', 'SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Reassign Ticket")
    public ResponseEntity<Void> reassign(
            @PathVariable Long id,
            @RequestParam Long newAgentId,
            @RequestParam String reason) {
        service.reassignToAgent(id, newAgentId, reason);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/escalate")
    @PreAuthorize("hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Escalate Ticket")
    public ResponseEntity<Void> escalate(
            @PathVariable Long id,
            @RequestParam String reason) {
        service.escalate(id, reason);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/first-response")
    @PreAuthorize("hasRole('SUPPORT_AGENT') or hasRole('SUPPORT_MANAGER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Record First Response (SLA Timer)")
    public ResponseEntity<Void> recordFirstResponse(@PathVariable Long id) {
        service.recordFirstResponse(id);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/resolve")
    // A tenant is admitted here as a coarse filter only: the service confines them to a CUSTOMER_SUPPORT ticket of
    // their own company and checks SUPPORT_MESSAGE_VIEW. Before this, only the platform's support roles could reach
    // resolve, and no tenant can hold those, so a company could never close out its own customer's ticket.
    @PreAuthorize("hasRole('SUPPORT_AGENT') or hasRole('SUPPORT_MANAGER') or hasAnyRole('COMPANY_OWNER', 'EMPLOYEE') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Resolve Ticket")
    public ResponseEntity<Void> resolve(
            @PathVariable Long id,
            @RequestParam String notes) {
        service.resolve(id, notes);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/close")
    // Same coarse filter as resolve above, with the same service-side confinement.
    @PreAuthorize("hasRole('SUPPORT_AGENT') or hasRole('SUPPORT_MANAGER') or hasAnyRole('COMPANY_OWNER', 'EMPLOYEE') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Close Ticket")
    public ResponseEntity<Void> close(@PathVariable Long id) {
        service.close(id);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/reopen")
    @PreAuthorize("hasAnyRole('SUPPORT_AGENT', 'SUPPORT_MANAGER', 'COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "Reopen Ticket")
    public ResponseEntity<Void> reopen(
            @PathVariable Long id,
            @RequestParam String reason) {
        service.reopen(id, reason);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{id}/satisfaction")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "Record Customer Satisfaction")
    public ResponseEntity<Void> recordSatisfaction(
            @PathVariable Long id,
            @RequestParam int rating,
            @RequestParam String feedback) {
        service.recordSatisfaction(id, rating, feedback);
        return ResponseEntity.ok().build();
    }

    @PatchMapping("/{id}")
    @PreAuthorize("hasRole('SUPPORT_MANAGER') or hasRole('SUPPORT_AGENT') or hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Update Ticket")
    public ResponseEntity<SupportTicketResponse> update(
            @PathVariable Long id,
            // Partial: only provided fields are applied; status goes through the guarded transitions (see SupportTicketServiceImpl.update).
            @Valid @RequestBody SupportTicketPatchRequest request) {
        return ResponseEntity.ok(service.update(id, request));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('COMPANY_OWNER') or hasAnyRole('SUPER_ADMIN', 'SYSTEM_ADMIN')")
    @Operation(summary = "Delete Ticket")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        service.delete(id);
        return ResponseEntity.noContent().build();
    }

    // Client-facing CUSTOMER_SUPPORT endpoints, against the client's own client-company and ownership-checked in the service; create()/getMyTickets() above are PLATFORM_SUPPORT only.

    @PostMapping("/client")
    @PreAuthorize("hasRole('CLIENT')")
    @Operation(summary = "[Client] Raise a Support Ticket")
    public ResponseEntity<SupportTicketResponse> createForClient(@Valid @RequestBody SupportTicketRequest request) {
        return new ResponseEntity<>(service.createForClient(request), HttpStatus.CREATED);
    }

    @GetMapping("/client/my")
    @PreAuthorize("hasRole('CLIENT')")
    @Operation(summary = "[Client] List My Tickets")
    public ResponseEntity<Page<SupportTicketResponse>> getMyClientTickets(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getMyClientTickets(SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/client/{id}")
    @PreAuthorize("hasRole('CLIENT')")
    @Operation(summary = "[Client] Get One of My Tickets")
    public ResponseEntity<SupportTicketResponse> getClientTicketById(@PathVariable Long id) {
        return ResponseEntity.ok(service.getClientTicketById(id));
    }

    // Staff-facing "Client Chat": this company's own clients' tickets, the counterpart to getAll()/getByStatus(), which return PLATFORM_SUPPORT only.

    @GetMapping("/company/client-tickets")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "[Staff] List This Company's Client Tickets")
    public ResponseEntity<Page<SupportTicketResponse>> getClientTicketsForCompany(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getClientTicketsForCompany(SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/company/client-tickets/status/{status}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "[Staff] List This Company's Client Tickets by Status")
    public ResponseEntity<Page<SupportTicketResponse>> getClientTicketsForCompanyByStatus(
            @PathVariable TicketStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.getClientTicketsForCompanyByStatus(status, SupportPaging.of(page, size, Sort.by("createdAt").descending())));
    }

    // Same paths/bodies/status codes as servicedesk-service so the Angular app works against both backends; any other ticket is a 404.

    @GetMapping("/company/client-tickets/{id}")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "[Staff] Get One of This Company's Client Tickets")
    public ResponseEntity<SupportTicketResponse> getClientTicketForCompany(@PathVariable Long id) {
        return ResponseEntity.ok(service.getClientTicketForCompany(id));
    }

    @GetMapping("/company/client-tickets/{id}/messages")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "[Staff] Get the Conversation on a Client Ticket")
    public ResponseEntity<List<SupportMessageResponse>> getClientTicketMessagesForCompany(@PathVariable Long id) {
        return ResponseEntity.ok(messageService.getClientTicketMessagesForCompany(id));
    }

    @PostMapping("/company/client-tickets/{id}/messages")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @Operation(summary = "[Staff] Reply on a Client Ticket")
    public ResponseEntity<SupportMessageResponse> replyToClientTicket(
            @PathVariable Long id,
            @Valid @RequestBody ClientTicketReplyRequest request) {
        return new ResponseEntity<>(messageService.replyToClientTicket(id, request), HttpStatus.CREATED);
    }
}
