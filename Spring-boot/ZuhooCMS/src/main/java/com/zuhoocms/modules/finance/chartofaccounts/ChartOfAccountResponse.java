package com.zuhoocms.modules.finance.chartofaccounts;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ChartOfAccountResponse {
    private Long id;
    private Long companyId;
    private String accountCode;
    private String accountName;
    private AccountType type;
    private BigDecimal balance;
    // Jackson would strip the "is" prefix from isHeaderAccount() and emit "headerAccount", which doesn't match the frontend's isHeaderAccount field.
    // The stripped "headerAccount"/"bankAccount" keys still ship alongside these, and are deliberately not suppressed:
    // the Flutter app reads them as a fallback (accounting_models.dart), so dropping them would be a wire removal a
    // client references. Angular reads only the pinned "is" spellings.
    @JsonProperty("isHeaderAccount")
    private boolean isHeaderAccount;
    @JsonProperty("isBankAccount")
    private boolean isBankAccount;
    private boolean allowDirectPosting;
    private boolean active;
    private String description;
    private String notes;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
