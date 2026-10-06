package com.zuhoocms.shared.subscription;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/** Catalog of subscription tiers; `code`, not this entity's id, is what Company.subscriptionPlan and SubscriptionHistory record, so a plan row can be edited or disabled without invalidating past history. */
@Entity
@Table(name = "subscription_plan_definitions",
       indexes = @Index(name = "idx_spd_code", columnList = "code", unique = true))
@Getter @Setter @Builder
@NoArgsConstructor @AllArgsConstructor
public class SubscriptionPlanDefinition {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 40)
    private String code;

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private BillingCycle billingCycle;

    @Column(nullable = false, precision = 15, scale = 2)
    private BigDecimal price;

    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();

    private LocalDateTime updatedAt;
}
