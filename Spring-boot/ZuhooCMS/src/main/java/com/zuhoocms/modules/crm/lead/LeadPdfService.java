package com.zuhoocms.modules.crm.lead;

import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyMapper;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.pdf.SimpleTablePdfRenderer;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class LeadPdfService {

    private static final List<String> HEADERS =
            List.of("ID", "Contact Name", "Company", "Email", "Phone", "Status", "Source", "Priority", "Assigned To");

    private final LeadService leadService;
    private final SimpleTablePdfRenderer pdfRenderer;
    private final CompanyRepository companyRepository;
    private final EmailBranding emailBranding;
    private final SecurityUtil securityUtil;

    /** Rows fetched per round trip while paging. */
    private static final int PAGE_SIZE = 500;

    /** Hard ceiling on one PDF: rendering an unbounded table would exhaust memory for whoever clicked the button. */
    private static final int MAX_ROWS = 20_000;

    @Transactional(readOnly = true)
    public byte[] generateListPdf(LeadStatus status) {
        // Pages through everything and says so in the subtitle when the ceiling is reached: a single PageRequest.of(0, 5000) captioned a company's 8,000 leads "5000 lead(s)" as fact.
        List<LeadResponse> leads = new ArrayList<>();
        boolean truncated = false;
        long totalAvailable = 0;

        for (int page = 0; ; page++) {
            Page<LeadResponse> slice = leadService.listLeads(
                    status, PageRequest.of(page, PAGE_SIZE, Sort.by("createdAt").descending()));
            totalAvailable = slice.getTotalElements();
            leads.addAll(slice.getContent());

            if (leads.size() >= MAX_ROWS) {
                truncated = leads.size() < totalAvailable || slice.hasNext();
                if (leads.size() > MAX_ROWS) {
                    leads = new ArrayList<>(leads.subList(0, MAX_ROWS));
                }
                break;
            }
            if (!slice.hasNext()) {
                break;
            }
        }

        List<List<String>> rows = new ArrayList<>();
        for (LeadResponse l : leads) {
            rows.add(toRow(l));
        }

        Company company = resolveCompany();
        EmailBranding.Data branding = emailBranding.from(company);
        String location = company != null ? CompanyMapper.formatAddress(company.getLocationDetail()) : null;
        String email = company != null ? company.getCompanyEmail() : null;

        String subtitle = truncated
                ? "Showing the first " + leads.size() + " of " + totalAvailable + " lead(s)"
                : leads.size() + " lead(s)";

        return pdfRenderer.render("Leads", subtitle, HEADERS, rows,
                branding.getCompanyName(), branding.getLogoUrl(), email, location);
    }

    private Company resolveCompany() {
        Long companyId = securityUtil.getCurrentCompanyId();
        return companyId != null ? companyRepository.findById(companyId).orElse(null) : null;
    }

    private List<String> toRow(LeadResponse l) {
        return List.of(
                String.valueOf(l.getId()),
                orDash(l.getContactName()),
                orDash(l.getCompanyName()),
                orDash(l.getEmail()),
                orDash(l.getPhone()),
                l.getStatus() != null ? l.getStatus().name() : "-",
                l.getSource() != null ? l.getSource().name() : "-",
                l.getPriority() != null ? l.getPriority().name() : "-",
                orDash(l.getAssignedToName())
        );
    }

    private String orDash(String v) {
        return v == null || v.isBlank() ? "-" : v;
    }
}
