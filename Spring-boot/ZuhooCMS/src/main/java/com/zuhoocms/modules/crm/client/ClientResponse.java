
package com.zuhoocms.modules.crm.client;

import com.zuhoocms.enums.ClientStatus;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Setter
public class ClientResponse {
    private Long id;
    private Long userId;
    private String firstName;
    private String lastName;
    private String email;
    private String phone;
    private String image;
    private String clientCompanyName;
    private String industry;
    private String website;
    private String taxId;
    private ClientStatus status;
    private boolean portalAccessEnabled;
    private Long accountManagerId;
    private String accountManagerName;
    private LocalDate onboardedAt;
    private LocalDateTime createdAt;

    private String billingAddress;
    private String shippingAddress;
    private String tags;
    private Integer employeeCount;
    private BigDecimal annualRevenue;
    private BigDecimal lifetimeValue;
    private Integer totalRequests;

    // Normalized shared-taxonomy tags (distinct from the legacy free-text `tags` field above).
    private java.util.List<com.zuhoocms.modules.crm.tag.TagResponse> tagList;

    // Set only right after creation when a possible duplicate was found; a nudge, not a block, since the Client is created either way.
    private com.zuhoocms.modules.crm.duplicate.DuplicateMatch possibleDuplicate;

    /** Only populated by inviteToPortal(), null elsewhere: the login is created either way, so false means "account ready, client not told" and needs its own message to staff. */
    private Boolean inviteEmailSent;
    /** Why the invite email failed, when inviteEmailSent is false. */
    private String inviteEmailError;
}
