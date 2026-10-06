package com.zuhoocms.modules.hrm.recruitment.candidate;

import com.zuhoocms.enums.ApplicationSource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface CandidateService {

    /** Finds or creates the candidate for this company+email (case-insensitive): contact details are refreshed from the latest application, the original source is left untouched. */
    default Candidate findOrCreate(Long companyId, String name, String email, String phone,
                            ApplicationSource source, String resumeUrl, String linkedInUrl, String portfolioUrl) {
        return findOrCreate(companyId, name, email, phone, source, resumeUrl, linkedInUrl, portfolioUrl, true);
    }

    /** @param refreshExistingDetails false for anonymous (careers page) applications, leaving an existing candidate's details untouched; the caller stores what was submitted on the application. */
    Candidate findOrCreate(Long companyId, String name, String email, String phone,
                            ApplicationSource source, String resumeUrl, String linkedInUrl, String portfolioUrl,
                            boolean refreshExistingDetails);

    CandidateResponse getById(Long id);

    Page<CandidateResponse> list(String q, Pageable pageable);

    CandidateResponse update(Long id, CandidateRequest request);

    void delete(Long id);
}
