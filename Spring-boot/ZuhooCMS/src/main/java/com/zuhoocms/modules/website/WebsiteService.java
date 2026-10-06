package com.zuhoocms.modules.website;

import com.zuhoocms.core.interceptor.UnfilteredReads;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Public company website. Every read runs through {@link UnfilteredReads} with the company_id resolved from the subdomain, or a signed-in user of company A sees company B's site filtered down to A's rows.
 * Lazy collections are initialised inside that read-only transaction, so serialising the result never hits a closed session.
 */
@org.springframework.stereotype.Service
@RequiredArgsConstructor
public class WebsiteService {

    private static final SecureRandom RANDOM = new SecureRandom();
    /** Crockford-style base32 without I, L, O, U - unambiguous when read out or typed. */
    private static final char[] CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toCharArray();
    private static final int CODE_LENGTH = 10;

    private static final List<String> TRACK_STEPS =
            List.of("SUBMITTED", "REVIEW", "NEED_DOCUMENTS", "APPROVED", "COMPLETED");
    private static final Map<String, String> TRACK_LABELS = Map.of(
            "SUBMITTED", "Request submitted",
            "REVIEW", "Under review",
            "NEED_DOCUMENTS", "Documents requested",
            "APPROVED", "Approved",
            "COMPLETED", "Completed");

    private final CompanyRepository companyRepository;
    private final WebsiteSettingsRepository settingsRepository;
    private final NavItemRepository navItemRepository;
    private final ServiceRepository serviceRepository;
    private final WebsiteContentRepository contentRepository;
    private final WebsitePersonRepository personRepository;
    private final FaqRepository faqRepository;
    private final PortalProjectRepository projectRepository;
    private final PricingPlanRepository pricingPlanRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final UnfilteredReads unfilteredReads;

    public Long resolveCompanyId(String host, String subdomainParam) {
        String subdomain = subdomainParam;
        if (subdomain == null && host != null) {
            String[] parts = host.split("\\.");
            if (parts.length > 2) subdomain = parts[0];
        }
        if (subdomain == null || subdomain.isBlank()) {
            throw new ResourceNotFoundException("Tenant not identified");
        }
        final String resolved = subdomain.toLowerCase().trim();
        Company company = companyRepository.findBySubdomain(resolved)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found: " + resolved));
        return company.getId();
    }

    public WebsiteSettings getSettings(Long companyId) {
        return unfilteredReads.run(() -> settingsRepository.findByCompanyId(companyId)
                .orElseGet(() -> defaultSettings(companyId)));
    }

    public List<NavNode> getNav(Long companyId) {
        List<NavItem> flat = unfilteredReads.run(() -> navItemRepository.findByCompanyIdOrderBySortOrderAsc(companyId));
        Map<Long, List<NavItem>> byParent = flat.stream()
                .collect(Collectors.groupingBy(n -> n.getParentId() == null ? -1L : n.getParentId()));
        return buildTree(byParent, -1L);
    }

    private List<NavNode> buildTree(Map<Long, List<NavItem>> byParent, Long parentId) {
        List<NavItem> children = byParent.getOrDefault(parentId, List.of());
        List<NavNode> nodes = new ArrayList<>();
        for (NavItem n : children) {
            nodes.add(new NavNode(n.getId(), n.getLabel(), n.getUrl(), n.isExternal(), n.isMega(),
                    buildTree(byParent, n.getId())));
        }
        return nodes;
    }

    public record NavNode(Long id, String label, String url, boolean external, boolean mega, List<NavNode> children) {}

    public List<com.zuhoocms.modules.website.Service> getServices(Long companyId, String category, String q) {
        return unfilteredReads.run(() -> {
            List<com.zuhoocms.modules.website.Service> list;
            if (q != null && !q.isBlank()) {
                list = serviceRepository.findByCompanyIdAndTitleContainingIgnoreCaseOrderByIdAsc(companyId, q.trim());
            } else if (category != null && !category.isBlank()) {
                list = serviceRepository.findByCompanyIdAndCategoryNameIgnoreCaseOrderByIdAsc(companyId, category.trim());
            } else {
                list = serviceRepository.findByCompanyIdOrderByIdAsc(companyId);
            }
            list.forEach(s -> s.getFeatures().size()); // initialise inside the transaction
            return list;
        });
    }

    public com.zuhoocms.modules.website.Service getService(Long companyId, String slug) {
        return unfilteredReads.run(() -> {
            com.zuhoocms.modules.website.Service s = serviceRepository.findBySlugAndCompanyId(slug, companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Service not found: " + slug));
            s.getFeatures().size();
            return s;
        });
    }

    public List<WebsiteContent> getBlogs(Long companyId, String category) {
        // "" = no category filter (a null String parameter inside LOWER() is bound as bytea by Postgres).
        String cat = category != null && !category.isBlank() ? category.trim() : "";
        return unfilteredReads.run(() ->
                contentRepository.findPublic(companyId, ContentType.POST, cat, LocalDateTime.now()));
    }

    public WebsiteContent getBlog(Long companyId, String slug) {
        return unfilteredReads.run(() ->
                contentRepository.findPublicBySlug(companyId, ContentType.POST, slug, LocalDateTime.now())
                        .orElseThrow(() -> new ResourceNotFoundException("Post not found: " + slug)));
    }

    public List<WebsitePerson> getTestimonials(Long companyId) {
        return unfilteredReads.run(() -> personRepository.findByCompanyIdAndType(companyId, PersonType.TESTIMONIAL));
    }

    public List<Faq> getFaqs(Long companyId) {
        return unfilteredReads.run(() -> faqRepository.findByCompanyId(companyId));
    }

    public List<WebsitePerson> getTeam(Long companyId) {
        return unfilteredReads.run(() -> personRepository.findByCompanyIdAndType(companyId, PersonType.TEAM_MEMBER));
    }

    public List<PortalProject> getProjects(Long companyId) {
        return unfilteredReads.run(() -> {
            List<PortalProject> list = projectRepository.findByCompanyId(companyId);
            list.forEach(p -> p.getTags().size());
            return list;
        });
    }

    public List<PricingPlan> getPricing(Long companyId) {
        return unfilteredReads.run(() -> {
            List<PricingPlan> list = pricingPlanRepository.findByCompanyId(companyId);
            list.forEach(p -> p.getFeatures().size());
            return list;
        });
    }

    public List<Stat> getStats(Long companyId) {
        return getSettings(companyId).getStats();
    }

    public WebsiteContent getPage(Long companyId, String slug) {
        return unfilteredReads.run(() ->
                contentRepository.findPublicBySlug(companyId, ContentType.PAGE, slug, LocalDateTime.now())
                        .orElseThrow(() -> new ResourceNotFoundException("Page not found: " + slug)));
    }

    @Transactional
    public void submitContact(Long companyId, WebsiteRequests.ContactRequest req) {
        // Persist as a service request for tracking; notifications handled by admin.
        ServiceRequest r = ServiceRequest.builder()
                .companyId(companyId)
                .code(generateCode())
                .name(req.name())
                .email(req.email())
                .phone(req.phone())
                .message((req.subject() != null ? "[" + req.subject() + "] " : "") + req.message())
                .status("SUBMITTED")
                .createdAt(LocalDateTime.now())
                .build();
        serviceRequestRepository.save(r);
    }

    @Transactional
    public void submitNewsletter(Long companyId, WebsiteRequests.NewsletterRequest req) {
        // In a real system this would subscribe the email; here we just record intent.
    }

    @Transactional
    public String createServiceRequest(Long companyId, WebsiteRequests.ServiceRequestPayload req) {
        if (req.email() == null || req.email().isBlank()) {
            // The email is what proves who may track the request later.
            throw new BadRequestException("Email is required");
        }
        String code = generateCode();
        ServiceRequest r = ServiceRequest.builder()
                .companyId(companyId)
                .code(code)
                .serviceId(req.serviceId())
                .serviceTitle(req.serviceTitle())
                .name(req.name())
                .email(req.email().trim())
                .phone(req.phone())
                .message(req.message())
                .status("SUBMITTED")
                .createdAt(LocalDateTime.now())
                .build();
        serviceRequestRepository.save(r);
        return code;
    }

    /** What the public tracking page shows - no name, phone or message. */
    public record TrackedRequest(String code, String service, String status, LocalDateTime submittedAt,
                                 List<TrackStep> steps) {}

    public record TrackStep(String label, boolean done) {}

    /**
     * Tracking needs the code AND the email it was submitted with; a wrong email is
     * indistinguishable from an unknown code, so codes cannot be probed for contact data.
     */
    public TrackedRequest trackRequest(Long companyId, String code, String email) {
        if (email == null || email.isBlank()) {
            throw new BadRequestException("Enter the email address you used for the request");
        }
        ServiceRequest r = unfilteredReads.run(() -> serviceRequestRepository.findByCodeAndCompanyId(code, companyId))
                .filter(sr -> sr.getEmail() != null && sr.getEmail().trim().equalsIgnoreCase(email.trim()))
                .orElseThrow(() -> new ResourceNotFoundException("Request not found. Please check the code and email."));
        int reached = TRACK_STEPS.indexOf(r.getStatus() == null ? "SUBMITTED" : r.getStatus());
        List<TrackStep> steps = new ArrayList<>();
        for (int i = 0; i < TRACK_STEPS.size(); i++) {
            steps.add(new TrackStep(TRACK_LABELS.get(TRACK_STEPS.get(i)), reached >= 0 && i <= reached));
        }
        String service = r.getServiceTitle() != null ? r.getServiceTitle() : "General enquiry";
        return new TrackedRequest(r.getCode(), service, r.getStatus(), r.getCreatedAt(), steps);
    }

    /** SR-YYYY- + 10 base32 chars from SecureRandom (~50 bits), retried on the rare collision. */
    private String generateCode() {
        for (int attempt = 0; attempt < 5; attempt++) {
            StringBuilder sb = new StringBuilder("SR-").append(LocalDateTime.now().getYear()).append('-');
            for (int i = 0; i < CODE_LENGTH; i++) {
                sb.append(CODE_ALPHABET[RANDOM.nextInt(CODE_ALPHABET.length)]);
            }
            String code = sb.toString();
            if (!serviceRequestRepository.existsByCode(code)) {
                return code;
            }
        }
        throw new IllegalStateException("Could not generate a unique request code");
    }

    private WebsiteSettings defaultSettings(Long companyId) {
        return WebsiteSettings.builder()
                .companyId(companyId)
                .companyName("Your Company")
                .tagline("Professional services, delivered with care")
                .primaryColor("#6D28D9")
                .secondaryColor("#2563EB")
                .gradient("linear-gradient(135deg, #6D28D9 0%, #2563EB 100%)")
                .font("'Inter', 'Plus Jakarta Sans', sans-serif")
                .radius(14)
                .buttonStyle("rounded")
                .darkMode(false)
                .navbarStyle("transparent")
                .footerStyle("dark")
                .animations(true)
                .spacing(1)
                .heroHeading("Welcome to Your Company")
                .heroSubheading("We help businesses grow with trusted, professional services.")
                .aboutText("About your company will appear here once configured from the dashboard.")
                .build();
    }
}
