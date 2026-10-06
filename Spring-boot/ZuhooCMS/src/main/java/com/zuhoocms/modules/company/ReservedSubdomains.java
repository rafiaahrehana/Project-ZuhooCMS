package com.zuhoocms.modules.company;

import com.zuhoocms.shared.exception.BadRequestException;

import java.util.Locale;
import java.util.Set;

/**
 * Subdomains no tenant may claim: they collide with platform hosts (app, api, cdn...) or let a tenant impersonate the platform (support, login, auth...).
 * Checked only on company creation, so tenants already holding one ("admin", "demo") keep it.
 */
public final class ReservedSubdomains {

    private ReservedSubdomains() {}

    public static final Set<String> RESERVED = Set.of(
            "www", "app", "api", "admin", "administrator", "demo", "mail", "email", "smtp", "imap", "pop",
            "static", "assets", "files", "file", "uploads", "cdn", "media", "img", "images",
            "support", "help", "helpdesk", "status", "docs", "doc", "blog", "portal", "auth", "login",
            "logout", "signin", "signup", "register", "account", "accounts", "dashboard", "gateway",
            "billing", "pay", "payment", "payments", "secure", "security", "sso", "oauth", "id",
            "platform", "system", "root", "internal", "dev", "staging", "test", "beta", "preview",
            "ws", "wss", "socket", "metrics", "monitor", "grafana", "zuhoo", "zuhoocms", "businessos");

    public static boolean isReserved(String subdomain) {
        return subdomain != null && RESERVED.contains(subdomain.trim().toLowerCase(Locale.ROOT));
    }

    public static void requireAllowed(String subdomain) {
        if (isReserved(subdomain)) {
            throw new BadRequestException("The subdomain '" + subdomain.trim().toLowerCase(Locale.ROOT)
                    + "' is reserved. Please choose another.");
        }
    }
}
