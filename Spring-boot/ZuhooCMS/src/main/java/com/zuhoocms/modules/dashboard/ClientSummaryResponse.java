package com.zuhoocms.modules.dashboard;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;

@Getter @Setter @Builder
public class ClientSummaryResponse {

    // Service requests (scoped to the logged-in client)
    long pendingRequests;
    long inProgressRequests;
    long completedRequests;

    // Invoices (scoped to the logged-in client)
    long unpaidInvoices;
    BigDecimal outstandingInvoiceAmount;

    /**
     * As on the tenant dashboard: "servicedesk" and/or "finance" when the counts above are zero only because the
     * query behind them failed. Empty when everything answered.
     */
    java.util.List<String> unavailableSections;
}
