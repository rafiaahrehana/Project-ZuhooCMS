package com.zuhoocms.shared.email;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.website.WebsiteSettings;
import com.zuhoocms.modules.website.WebsiteSettingsRepository;
import lombok.Builder;
import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class EmailBranding {

    private final WebsiteSettingsRepository websiteSettingsRepository;

    private final String frontendUrl;

    public EmailBranding(WebsiteSettingsRepository websiteSettingsRepository,
                         @Value("${app.frontend-url}") String frontendUrl) {
        this.websiteSettingsRepository = websiteSettingsRepository;
        this.frontendUrl = primaryFrontendUrl(frontendUrl);
    }

    /** app.frontend-url doubles as the CORS allow-list, so it may be a comma-separated list with wildcards; mail links need one concrete origin, the first entry without a wildcard. */
    public static String primaryFrontendUrl(String raw) {
        if (raw == null) {
            return "";
        }
        for (String entry : raw.split(",")) {
            String candidate = entry.trim();
            if (!candidate.isEmpty() && !candidate.contains("*")) {
                while (candidate.endsWith("/")) {
                    candidate = candidate.substring(0, candidate.length() - 1);
                }
                return candidate;
            }
        }
        return "";
    }

    public Data getPlatformBranding() {
        return Data.builder()
                .companyId(null)
                .companyName("businessos")
                .logoUrl(frontendUrl + "/images/logo.png")
                .primaryColor("#1e3a5f")
                .build();
    }

    public Data from(Company company) {
        if (company == null) {
            return getPlatformBranding();
        }
        return websiteSettingsRepository.findByCompanyId(company.getId())
                .map(settings -> Data.builder()
                        .companyId(company.getId())
                        .companyName(company.getCompanyName())
                        .logoUrl(settings.getLogoUrl() != null && !settings.getLogoUrl().isEmpty() ? settings.getLogoUrl() : (frontendUrl + "/images/logo.png"))
                        .primaryColor(settings.getPrimaryColor() != null && !settings.getPrimaryColor().isEmpty() ? settings.getPrimaryColor() : "#1e3a5f")
                        .build())
                .orElseGet(() -> Data.builder()
                        .companyId(company.getId())
                        .companyName(company.getCompanyName())
                        .logoUrl(frontendUrl + "/images/logo.png")
                        .primaryColor("#1e3a5f")
                        .build());
    }

    @Getter
    @Builder
    public static class Data {
        private Long companyId;
        private String companyName;
        private String logoUrl;
        private String primaryColor;
    }
}