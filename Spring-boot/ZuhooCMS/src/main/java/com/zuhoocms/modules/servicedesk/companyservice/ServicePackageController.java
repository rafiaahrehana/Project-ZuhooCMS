package com.zuhoocms.modules.servicedesk.companyservice;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import com.zuhoocms.enums.SubscriptionStatus;

import java.util.List;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/packages")
public class ServicePackageController {

    private final ServicePackageService packageService;

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PostMapping
    public ResponseEntity<ServicePackageResponse> create(
            @Valid @RequestBody ServicePackageRequest request) {
        return new ResponseEntity<>(packageService.create(request), HttpStatus.CREATED);
    }

    /** Includes inactive packages. */
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @GetMapping
    public ResponseEntity<Page<ServicePackageResponse>> listAll(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(packageService.listAll(
            PageRequest.of(page, size, Sort.by("createdAt").descending())));
    }

    /** Intentionally open to any authenticated user, including CLIENT. */
    @GetMapping("/active")
    public ResponseEntity<List<ServicePackageResponse>> listActive() {
        return ResponseEntity.ok(packageService.listActive());
    }

    @GetMapping("/{id}")
    public ResponseEntity<ServicePackageResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(packageService.getById(id));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PutMapping("/{id}")
    public ResponseEntity<ServicePackageResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody ServicePackageRequest request) {
        return ResponseEntity.ok(packageService.update(id, request));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PatchMapping("/{id}/toggle")
    public ResponseEntity<ServicePackageResponse> toggle(@PathVariable Long id) {
        return ResponseEntity.ok(packageService.toggleActive(id));
    }

    /** Soft-delete, refused while the package has active subscriptions. */
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @DeleteMapping("/{id}")
    public ResponseEntity<String> delete(@PathVariable Long id) {
        packageService.delete(id);
        return ResponseEntity.ok("Package deleted successfully");
    }

    /** A CLIENT subscribes themselves; staff subscribe on a client's behalf by passing clientId in the body. */
    @PostMapping("/subscribe")
    public ResponseEntity<PackageSubscriptionResponse> subscribe(
            @Valid @RequestBody SubscribeRequest request) {
        return new ResponseEntity<>(packageService.subscribe(request), HttpStatus.CREATED);
    }

    /** Activates a PENDING_PAYMENT subscription by hand, standing in for the payment webhook. */
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PatchMapping("/subscriptions/{id}/activate")
    public ResponseEntity<PackageSubscriptionResponse> activate(@PathVariable Long id) {
        return ResponseEntity.ok(packageService.activate(id));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PatchMapping("/subscriptions/{id}/suspend")
    public ResponseEntity<PackageSubscriptionResponse> suspend(
            @PathVariable Long id,
            @RequestParam(required = false) String reason) {
        return ResponseEntity.ok(packageService.suspend(id, reason));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @PatchMapping("/subscriptions/{id}/reactivate")
    public ResponseEntity<PackageSubscriptionResponse> reactivate(@PathVariable Long id) {
        return ResponseEntity.ok(packageService.reactivate(id));
    }

    /** Intentionally open to CLIENT as well as staff. */
    @PatchMapping("/subscriptions/{id}/cancel")
    public ResponseEntity<PackageSubscriptionResponse> cancel(
            @PathVariable Long id,
            @RequestParam(required = false) String reason) {
        return ResponseEntity.ok(packageService.cancel(id, reason));
    }

    @GetMapping("/subscriptions/{id}")
    public ResponseEntity<PackageSubscriptionResponse> getSubscriptionById(
            @PathVariable Long id) {
        return ResponseEntity.ok(packageService.getSubscriptionById(id));
    }

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @GetMapping("/subscriptions")
    public ResponseEntity<Page<PackageSubscriptionResponse>> listSubscriptions(
            @RequestParam(required = false) SubscriptionStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(packageService.listSubscriptions(status,
            PageRequest.of(page, size, Sort.by("createdAt").descending())));
    }

    @GetMapping("/subscriptions/my")
    public ResponseEntity<Page<PackageSubscriptionResponse>> listMySubscriptions(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(packageService.listMySubscriptions(
            PageRequest.of(page, size, Sort.by("createdAt").descending())));
    }
}
