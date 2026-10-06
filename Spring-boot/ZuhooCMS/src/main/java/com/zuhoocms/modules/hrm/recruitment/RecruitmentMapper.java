package com.zuhoocms.modules.hrm.recruitment;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.modules.hrm.recruitment.candidate.Candidate;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationResponse;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;

public class RecruitmentMapper {

    /*
     * Every association here goes through SoftDeletedProxies.loadable()/id(), not a != null check: a lazy proxy to a
     * soft-deleted row is non-null and throws EntityNotFoundException the moment it is read (BaseEntity's
     * @SQLRestriction("deleted = false")). DELETE /api/recruitment/candidates/{id} soft-deletes the candidate but
     * leaves its applications live, which 500'd the whole application list and every detail view behind it.
     * Ids still come off the FK, and the name/phone fall back to the applicant* values denormalised on the row.
     */
    public static JobApplicationResponse toJobApplicationResponse(JobApplication a) {
        JobPosting jp = SoftDeletedProxies.loadable(a.getJobPosting());
        User reviewerUser = SoftDeletedProxies.loadable(a.getReviewedBy());
        Candidate c = SoftDeletedProxies.loadable(a.getCandidate());

        JobApplicationResponse r = new JobApplicationResponse();
        r.setId(a.getId());
        r.setCandidateId(SoftDeletedProxies.id(a.getCandidate()));
        r.setCandidateName(c != null && c.getName() != null ? c.getName() : a.getApplicantName());
        r.setCandidateEmail(c != null ? c.getEmail() : null);
        r.setCandidatePhone(c != null && c.getPhone() != null ? c.getPhone() : a.getApplicantPhone());
        // Documents submitted with this application win over the candidate's stored ones.
        r.setResumeUrl(a.getResumeUrl() != null ? a.getResumeUrl() : c != null ? c.getResumeUrl() : null);
        r.setLinkedInUrl(a.getLinkedInUrl() != null ? a.getLinkedInUrl() : c != null ? c.getLinkedInUrl() : null);
        r.setPortfolioUrl(a.getPortfolioUrl() != null ? a.getPortfolioUrl() : c != null ? c.getPortfolioUrl() : null);
        r.setCoverLetter(a.getCoverLetter());
        r.setSource(a.getSource());
        r.setStatus(a.getStatus());
        r.setNotes(a.getInterviewNotes());
        r.setJobPostingId(SoftDeletedProxies.id(a.getJobPosting()));
        r.setJobPostingTitle(jp != null ? jp.getTitle() : null);
        r.setReviewedById(SoftDeletedProxies.id(a.getReviewedBy()));
        r.setReviewedByName(reviewerUser != null ? reviewerUser.getFullName() : null);
        // Terminating an employee soft-deletes the row, so the hired employee's id comes off the FK rather than the proxy.
        r.setConvertedEmployeeId(SoftDeletedProxies.id(a.getConvertedEmployee()));
        r.setConvertedAt(a.getConvertedAt());
        r.setScoreEducation(a.getScoreEducation());
        r.setScoreExperience(a.getScoreExperience());
        r.setScoreTechnicalSkills(a.getScoreTechnicalSkills());
        r.setScoreInterview(a.getScoreInterview());
        r.setScoreCommunication(a.getScoreCommunication());
        r.setOverallScore(a.getOverallScore());
        r.setAtsScore(a.getAtsScore());
        r.setAtsMatchedRequiredSkills(a.getAtsMatchedRequiredSkills());
        r.setAtsMissingRequiredSkills(a.getAtsMissingRequiredSkills());
        r.setAtsMatchedPreferredSkills(a.getAtsMatchedPreferredSkills());
        r.setAtsExtractedExperienceYears(a.getAtsExtractedExperienceYears());
        r.setAtsMeetsEducationRequirement(a.getAtsMeetsEducationRequirement());
        r.setAtsParseStatus(a.getAtsParseStatus());
        r.setAtsParsedAt(a.getAtsParsedAt());
        r.setCreatedAt(a.getCreatedAt());
        return r;
    }
}
