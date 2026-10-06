package com.zuhoocms.modules.crm.capture;

import com.zuhoocms.enums.LeadSource;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.modules.website.WebsiteService;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Anonymous lead capture for the marketing site and tenant portal contact forms; unauthenticated by design (see PUBLIC_ENDPOINTS in SecurityConfig).
 *
 *  - Always answers with the same generic success body: "this email already exists" would let anyone probe a company's CRM.
 *  - Duplicate submissions (same email or phone, same company) are accepted and dropped, so a double submit does not double the pipeline.
 *  - The honeypot field is not rate limiting; put the endpoint behind one (e.g. AWS WAF) in production.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/public/crm")
public class PublicLeadCaptureController {

    private final LeadRepository leadRepository;
    private final CompanyRepository companyRepository;
    private final WebsiteService websiteService;
    private final NotificationService notificationService;

    /** Which company receives leads from the PLATFORM's landing page (tenant portals resolve by subdomain); unset, submissions are logged and dropped rather than failed at the visitor. */
    @Value("${app.crm.platform-lead-company-id:}")
    private String platformLeadCompanyId;

    @PostMapping("/leads")
    @Transactional
    public ResponseEntity<Map<String, String>> capture(@Valid @RequestBody PublicLeadRequest request) {
        // Bots fill every field; humans never see this one.
        if (request.getWebsite() != null && !request.getWebsite().isBlank()) {
            return ok();
        }
        // Email or phone - a lead reachable by neither is not a lead.
        boolean hasEmail = request.getEmail() != null && !request.getEmail().isBlank();
        boolean hasPhone = request.getPhone() != null && !request.getPhone().isBlank();
        if (!hasEmail && !hasPhone) {
            return ok(); // indistinguishable from success, on purpose
        }

        Company company = resolveTargetCompany(request.getSubdomain());
        if (company == null) {
            log.warn("Public lead dropped - no target company (subdomain={}, platform id configured={})",
                    request.getSubdomain(), !platformLeadCompanyId.isBlank());
            return ok();
        }

        // Normalised exactly as the manual-create and CSV-import paths do, or "Bob@X.com " and "bob@x.com" become two leads for one person.
        String email = com.zuhoocms.modules.crm.support.EmailMatching.normalise(request.getEmail());
        String phone = com.zuhoocms.modules.crm.support.PhoneMatching.normaliseForStorage(request.getPhone());

        // Same-company dedupe; the visitor is told nothing either way.
        if (email != null
                && leadRepository.existsByEmailIgnoringCase(email, company.getId(), null)) {
            return ok();
        }
        String phoneKey = com.zuhoocms.modules.crm.support.PhoneMatching.matchKey(phone);
        if (phoneKey != null
                && leadRepository.existsByNormalisedPhone(phoneKey, company.getId(), null)) {
            return ok();
        }

        Lead lead = new Lead();
        lead.setContactName(request.getName().trim());
        lead.setCompanyName(trimOrNull(request.getCompanyName()));
        lead.setEmail(email);
        lead.setPhone(phone);
        lead.setNotes(trimOrNull(request.getMessage()));
        lead.setStatus(LeadStatus.NEW);
        lead.setSource(LeadSource.WEBSITE);
        lead.setCompany(company);
        leadRepository.save(lead);

        notifyOwner(company, lead);
        return ok();
    }

    private Company resolveTargetCompany(String subdomain) {
        if (subdomain != null && !subdomain.isBlank()) {
            try {
                Long id = websiteService.resolveCompanyId(null, subdomain);
                return companyRepository.findById(id).orElse(null);
            } catch (Exception e) {
                return null; // unknown subdomain - drop silently, do not confirm which subdomains exist
            }
        }
        if (platformLeadCompanyId.isBlank()) return null;
        try {
            return companyRepository.findById(Long.parseLong(platformLeadCompanyId.trim())).orElse(null);
        } catch (NumberFormatException e) {
            log.warn("app.crm.platform-lead-company-id is not a number: {}", platformLeadCompanyId);
            return null;
        }
    }

    /** New inbound lead has no assignee yet, so the company owner is told. */
    private void notifyOwner(Company company, Lead lead) {
        if (company.getOwner() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.LEAD_ASSIGNED,
                "New website lead",
                "\"" + lead.getContactName() + "\" reached out via the website"
                        + (lead.getEmail() != null ? " (" + lead.getEmail() + ")" : "") + ".",
                "/crm/leads",
                company.getOwner().getId(),
                company.getId()
        ));
    }

    private static String trimOrNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static ResponseEntity<Map<String, String>> ok() {
        return ResponseEntity.ok(Map.of("message", "Thanks - we will be in touch shortly."));
    }
}
