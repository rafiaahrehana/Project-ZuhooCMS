package com.zuhoocms.modules.crm.lead;

import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyMapper;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.pdf.SimpleTablePdfRenderer;
import lombok.RequiredArgsConstructor;
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

    @Transactional(readOnly = true)
    public byte[] generateListPdf(LeadStatus status) {
        List<LeadResponse> leads = leadService.listLeads(
                status, PageRequest.of(0, 5000, Sort.by("createdAt").descending())
        ).getContent();

        List<List<String>> rows = new ArrayList<>();
        for (LeadResponse l : leads) {
            rows.add(toRow(l));
        }

        Company company = resolveCompany();
        EmailBranding.Data branding = emailBranding.from(company);
        String location = company != null ? CompanyMapper.formatAddress(company.getLocationDetail()) : null;
        String email = company != null ? company.getCompanyEmail() : null;

        return pdfRenderer.render("Leads", leads.size() + " lead(s)", HEADERS, rows,
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
