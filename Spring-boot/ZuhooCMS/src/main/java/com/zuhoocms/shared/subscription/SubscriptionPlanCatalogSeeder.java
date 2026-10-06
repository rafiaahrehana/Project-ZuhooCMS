package com.zuhoocms.shared.subscription;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

/** Seeds the FREE/STARTER/PRO/ENTERPRISE rows on every boot: companies already hold those codes in subscriptionPlan, so plan lookups break unless each resolves to a catalog row. */
@Component
@RequiredArgsConstructor
public class SubscriptionPlanCatalogSeeder implements CommandLineRunner {

    private final SubscriptionPlanDefinitionRepository repository;

    @Override
    public void run(String... args) {
        seed("FREE", "Free", "Basic support, limited users, community access.", BillingCycle.MONTHLY, BigDecimal.ZERO);
        seed("STARTER", "Starter", "Email support, up to 10 users, standard integrations.", BillingCycle.MONTHLY, new BigDecimal("4900"));
        seed("PRO", "Pro", "Priority support, unlimited users, advanced integrations.", BillingCycle.MONTHLY, new BigDecimal("9900"));
        seed("ENTERPRISE", "Enterprise", "24/7 phone support, dedicated account manager, custom development.", BillingCycle.MONTHLY, new BigDecimal("19900"));
    }

    private void seed(String code, String name, String description, BillingCycle cycle, BigDecimal price) {
        if (!repository.existsByCodeIgnoreCase(code)) {
            repository.save(SubscriptionPlanDefinition.builder()
                    .code(code)
                    .name(name)
                    .description(description)
                    .billingCycle(cycle)
                    .price(price)
                    .active(true)
                    .build());
        }
    }
}
