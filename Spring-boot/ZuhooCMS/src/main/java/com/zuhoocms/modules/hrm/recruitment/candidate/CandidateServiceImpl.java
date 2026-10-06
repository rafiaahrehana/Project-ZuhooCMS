package com.zuhoocms.modules.hrm.recruitment.candidate;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class CandidateServiceImpl implements CandidateService {

    private final CandidateRepository candidateRepository;
    private final JobApplicationRepository applicationRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public Candidate findOrCreate(Long companyId, String name, String email, String phone,
                                   ApplicationSource source, String resumeUrl, String linkedInUrl, String portfolioUrl,
                                   boolean refreshExistingDetails) {
        if (email == null || email.isBlank()) {
            throw new BadRequestException("Applicant email is required");
        }
        String normalizedEmail = email.toLowerCase().trim();
        // Serialise find-or-create per (company, email) - see lockCompanyEmail.
        candidateRepository.lockCompanyEmail(companyId, normalizedEmail);
        return candidateRepository.findByCompanyIdAndEmailIgnoreCaseOrderByIdAsc(companyId, normalizedEmail)
            .stream().findFirst()
            .map(existing -> {
                if (!refreshExistingDetails) {
                    return existing;
                }
                // Refresh contact details from the latest application; the original source stays as first recorded.
                if (name != null) existing.setName(name);
                if (phone != null) existing.setPhone(phone);
                if (resumeUrl != null) existing.setResumeUrl(resumeUrl);
                if (linkedInUrl != null) existing.setLinkedInUrl(linkedInUrl);
                if (portfolioUrl != null) existing.setPortfolioUrl(portfolioUrl);
                return existing;
            })
            .orElseGet(() -> {
                Company companyRef = new Company();
                companyRef.setId(companyId);
                Candidate candidate = Candidate.builder()
                    .company(companyRef)
                    .name(name)
                    .email(normalizedEmail)
                    .phone(phone)
                    .resumeUrl(resumeUrl)
                    .linkedInUrl(linkedInUrl)
                    .portfolioUrl(portfolioUrl)
                    .source(source)
                    .build();
                return candidateRepository.save(candidate);
            });
    }

    @Override
    @Transactional(readOnly = true)
    public CandidateResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Candidate candidate = findInTenant(id);
        CandidateResponse response = CandidateResponse.from(candidate);
        response.setApplicationCount(applicationRepository.countByCompanyIdAndCandidateId(requireCompanyId(), id));
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public Page<CandidateResponse> list(String q, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_VIEW);
        Long companyId = requireCompanyId();
        Page<Candidate> page = (q != null && !q.isBlank())
            ? candidateRepository.search(companyId, q.trim(), pageable)
            : candidateRepository.findByCompanyId(companyId, pageable);
        // One grouped count query for the page instead of one count per row.
        java.util.Map<Long, Long> counts = new java.util.HashMap<>();
        java.util.List<Long> ids = page.getContent().stream().map(Candidate::getId).toList();
        if (!ids.isEmpty()) {
            for (Object[] row : candidateRepository.countApplicationsByCandidate(companyId, ids)) {
                counts.put((Long) row[0], ((Number) row[1]).longValue());
            }
        }
        return page.map(c -> {
            CandidateResponse r = CandidateResponse.from(c);
            r.setApplicationCount(counts.getOrDefault(c.getId(), 0L));
            return r;
        });
    }

    @Override
    @Transactional
    public CandidateResponse update(Long id, CandidateRequest request) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_UPDATE);
        Candidate candidate = findInTenant(id);
        if (request.getName() != null && !request.getName().isBlank()) candidate.setName(request.getName().trim());
        if (request.getEmail() != null && !request.getEmail().isBlank()) candidate.setEmail(request.getEmail().toLowerCase().trim());
        // Null-skipped, like name, email and source already were. These seven used to be assigned outright, so an
        // update carrying only the name and e-mail it validates erased the candidate's phone, resume link,
        // LinkedIn, portfolio, current title, skills and notes - everything a recruiter had gathered about them.
        //
        // The resume is guarded on the request value rather than inside requireOwn, because that helper treats a
        // null url as "clear the column": right for an explicit clear, wrong for an absent key.
        if (request.getPhone() != null) candidate.setPhone(request.getPhone());
        if (request.getResumeUrl() != null) {
            candidate.setResumeUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(
                    request.getResumeUrl(), candidate.getResumeUrl()));
        }
        if (request.getLinkedInUrl() != null) candidate.setLinkedInUrl(request.getLinkedInUrl());
        if (request.getPortfolioUrl() != null) candidate.setPortfolioUrl(request.getPortfolioUrl());
        if (request.getCurrentTitle() != null) candidate.setCurrentTitle(request.getCurrentTitle());
        if (request.getSkills() != null) candidate.setSkills(request.getSkills());
        if (request.getSource() != null) candidate.setSource(request.getSource());
        if (request.getNotes() != null) candidate.setNotes(request.getNotes());
        CandidateResponse response = CandidateResponse.from(candidate);
        response.setApplicationCount(applicationRepository.countByCompanyIdAndCandidateId(requireCompanyId(), id));
        return response;
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.APPLICATION_DELETE);
        Candidate candidate = findInTenant(id);
        // The applications, interviews and offers behind this candidate stay live and every view of them reads the
        // candidate through a lazy proxy, which throws once the row is soft-deleted. One UPDATE here pins the name
        // and phone onto those applications, so those lists keep showing who they are with no extra lookup per row.
        applicationRepository.backfillApplicantDetails(
            requireCompanyId(), id, candidate.getName(), candidate.getPhone());
        candidate.softDelete();
    }

    private Candidate findInTenant(Long id) {
        return candidateRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Candidate not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
