package com.zuhoocms.modules.itam.software;

import jakarta.validation.constraints.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;

// AllArgsConstructor is package-private so Jackson cannot use it as a creator: a body omitting a primitive field failed with "Cannot map null into type int/boolean" before @Valid ran; no-args+setters leaves missing primitives at 0/false.
@Data @NoArgsConstructor @AllArgsConstructor(access = AccessLevel.PACKAGE) @Builder
public class SoftwareLicenseRequest {

    @NotBlank(message = "License key is required")
    @Size(max = 200, message = "License key must be at most 200 characters")
    private String licenseKey;

    @NotBlank(message = "Software name is required")
    private String softwareName;

    @NotBlank(message = "Publisher is required")
    private String publisher;

    private String version;

    @NotNull(message = "License type is required")
    private LicenseType licenseType;

    @Min(value = 1, message = "Total seats must be at least 1")
    private int totalSeatsLicensed;

    @NotNull(message = "License purchase date is required")
    private LocalDate licensePurchaseDate;

    // 0 is valid for PERPETUAL/OPEN_SOURCE; SUBSCRIPTION/TRIAL must exceed 0 - see SoftwareLicenseServiceImpl.validateByType().
    @NotNull(message = "License cost is required")
    @DecimalMin(value = "0.0", message = "License cost cannot be negative")
    private BigDecimal licenseCost;

    // Optional for PERPETUAL/OPEN_SOURCE; required for SUBSCRIPTION/TRIAL - see validateByType().
    private LocalDate licenseExpiryDate;

    @NotNull(message = "Renewal type is required")
    private LicenseRenewalType renewalType;

    private LocalDate nextRenewalDate;
    private BigDecimal renewalCost;

    private String vendor;
    private String accountEmail;
    private String licenseUrl;

    private String installationLocation;
    private int estimatedUserCount;
    private String complianceNotes;
    private String notes;
    private String renewalNotes;

    // Boolean, not boolean: the form never sends autoRenew, and a missing primitive fails with "Cannot map `null` into type `boolean`".
    private Boolean autoRenew;

    public boolean isAutoRenewOrDefault() {
        return autoRenew == null || autoRenew;
    }
}
