package com.zuhoocms.modules.hrm.payroll.run;

import com.zuhoocms.enums.PaymentMethod;
import com.zuhoocms.modules.hrm.payroll.PayrollPeriods;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/hr/payroll-runs")
@PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
public class PayrollRunController {

    private final PayrollRunService service;

    public record CreateRunRequest(
            @NotNull(message = PayrollPeriods.MONTH_MESSAGE)
            @Min(value = 1, message = PayrollPeriods.MONTH_MESSAGE)
            @Max(value = 12, message = PayrollPeriods.MONTH_MESSAGE)
            Integer month,
            @NotNull(message = PayrollPeriods.YEAR_MESSAGE)
            @Min(value = 2000, message = PayrollPeriods.YEAR_MESSAGE)
            @Max(value = 2100, message = PayrollPeriods.YEAR_MESSAGE)
            Integer year,
            @Size(max = 2000, message = "Remarks cannot exceed 2000 characters")
            String remarks) {}

    public record RejectRequest(
            @NotBlank(message = "Rejection reason is required")
            @Size(max = 2000, message = "Rejection reason cannot exceed 2000 characters")
            String reason) {}

    public record PayRequest(
            @NotNull(message = "Payment method is required")
            PaymentMethod paymentMethod,
            @Size(max = 20, message = "Reference prefix cannot exceed 20 characters")
            String referencePrefix,
            LocalDate paymentDate) {}

    @GetMapping
    public ResponseEntity<List<PayrollRun>> list() {
        return ResponseEntity.ok(service.list());
    }

    /** The run for one period, or 204 if none exists yet. */
    @GetMapping("/period")
    public ResponseEntity<PayrollRun> forPeriod(@RequestParam int month, @RequestParam int year) {
        PayrollRun run = service.getForPeriod(month, year);
        return run == null ? ResponseEntity.noContent().build() : ResponseEntity.ok(run);
    }

    @PostMapping
    public ResponseEntity<PayrollRun> create(@Valid @RequestBody CreateRunRequest request) {
        return new ResponseEntity<>(service.create(request.month(), request.year(), request.remarks()), HttpStatus.CREATED);
    }

    @PostMapping("/{id}/recalculate")
    public ResponseEntity<PayrollRun> recalculate(@PathVariable Long id) {
        return ResponseEntity.ok(service.recalculate(id));
    }

    @PostMapping("/{id}/submit")
    public ResponseEntity<PayrollRun> submit(@PathVariable Long id) {
        return ResponseEntity.ok(service.submit(id));
    }

    @PostMapping("/{id}/approve")
    public ResponseEntity<PayrollRun> approve(@PathVariable Long id) {
        return ResponseEntity.ok(service.approve(id));
    }

    @PostMapping("/{id}/reject")
    public ResponseEntity<PayrollRun> reject(@PathVariable Long id, @Valid @RequestBody RejectRequest request) {
        return ResponseEntity.ok(service.reject(id, request.reason()));
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<PayrollRun> cancel(@PathVariable Long id) {
        return ResponseEntity.ok(service.cancel(id));
    }

    @PostMapping("/{id}/pay")
    public ResponseEntity<PayrollRun> pay(@PathVariable Long id, @Valid @RequestBody PayRequest request) {
        return ResponseEntity.ok(service.pay(id, request.paymentMethod(), request.referencePrefix(), request.paymentDate()));
    }
}
