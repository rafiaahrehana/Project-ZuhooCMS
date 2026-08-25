package com.zuhoocms.modules.hrm.recruitment;


import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.modules.hrm.employee.EmployeeResponse;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.HireApplicationRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationResponse;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface RecruitmentService {

    JobApplicationResponse apply(Long jobPostingId, JobApplicationRequest request);

    JobApplicationResponse getById(Long id);

    Page<JobApplicationResponse> listByPosting(Long jobPostingId, Pageable pageable);

    Page<JobApplicationResponse> listAll(ApplicationStatus status, Pageable pageable);

    JobApplicationResponse updateStatus(Long id, ApplicationStatus status, String notes);

    /** Sets whichever subscores are provided and recomputes overallScore - see RecruitmentServiceImpl for the weighting. */
    JobApplicationResponse evaluate(Long id, com.zuhoocms.modules.hrm.recruitment.jobapplication.EvaluateCandidateRequest request);

    /** ADMIN / OWNER: hire an OFFERED candidate — creates the Employee (+ portal user)
     * in one transaction and marks the application HIRED. */
    EmployeeResponse hire(Long id, HireApplicationRequest request);

    void delete(Long id);
}
