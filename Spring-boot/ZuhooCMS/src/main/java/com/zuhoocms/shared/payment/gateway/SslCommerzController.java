package com.zuhoocms.shared.payment.gateway;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Map;

@RestController
@RequestMapping("/api/payments/sslcommerz")
@RequiredArgsConstructor
public class SslCommerzController {

    private final SslCommerzService sslCommerzService;

    @Value("${app.frontend-url}")
    private String frontendUrl;

    /** Starts a checkout for company staff and clients; the per-purpose ownership checks in the service still apply. */
    @PostMapping("/initiate")
    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE', 'CLIENT')")
    public ResponseEntity<Map<String, String>> initiate(@Valid @RequestBody InitiateGatewayPaymentRequest request) {
        String url = sslCommerzService.initiate(
            request.getPurpose(), request.getTargetId(), request.getAmount());
        return ResponseEntity.ok(Map.of("gatewayUrl", url));
    }

    /* The endpoints below are called by SSLCommerz itself: public (whitelisted in SecurityConfig) and redirect the payer to the frontend result page. */

    @PostMapping("/callback/success")
    public ResponseEntity<Void> success(@RequestParam Map<String, String> params) {
        GatewayTransactionStatus status = sslCommerzService.handleSuccess(params);
        return redirect(status.name(), params.get("tran_id"));
    }

    @PostMapping("/callback/fail")
    public ResponseEntity<Void> fail(@RequestParam Map<String, String> params) {
        sslCommerzService.markFailed(params.get("tran_id"));
        return redirect("FAILED", params.get("tran_id"));
    }

    @PostMapping("/callback/cancel")
    public ResponseEntity<Void> cancel(@RequestParam Map<String, String> params) {
        sslCommerzService.markCancelled(params.get("tran_id"));
        return redirect("CANCELLED", params.get("tran_id"));
    }

    /** Server-to-server IPN - same validated handler, idempotent. */
    @PostMapping("/ipn")
    public ResponseEntity<String> ipn(@RequestParam Map<String, String> params) {
        sslCommerzService.handleSuccess(params);
        return ResponseEntity.ok("OK");
    }

    private ResponseEntity<Void> redirect(String status, String tranId) {
        HttpHeaders headers = new HttpHeaders();
        headers.add(HttpHeaders.LOCATION,
            frontendUrl + "/payment-result?status=" + status + "&tranId=" + (tranId == null ? "" : tranId));
        return new ResponseEntity<>(headers, HttpStatus.FOUND);
    }
}
