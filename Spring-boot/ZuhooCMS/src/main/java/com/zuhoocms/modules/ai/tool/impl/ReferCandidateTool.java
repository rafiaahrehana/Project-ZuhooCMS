package com.zuhoocms.modules.ai.tool.impl;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.enums.JobPostingStatus;
import com.zuhoocms.modules.ai.tool.AiTool;
import com.zuhoocms.modules.ai.tool.AiToolResult;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.recruitment.RecruitmentService;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRequest;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationResponse;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPostingRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor
public class ReferCandidateTool implements AiTool {

    private final RecruitmentService recruitmentService;
    private final JobPostingRepository jobPostingRepository;
    private final EmployeeRepository employeeRepository;

    @Override
    public String name() {
        return "refer_candidate";
    }

    @Override
    public String description() {
        return "Refer a friend or contact for an open job posting - submits their application marked as an employee referral, traceable back to the employee.";
    }

    @Override
    public Map<String, Object> parametersSchema() {
        return Map.of(
            "type", "object",
            "properties", Map.of(
                "jobTitle", Map.of("type", "string", "description", "The open position's title, or a keyword from it"),
                "candidateName", Map.of("type", "string"),
                "candidateEmail", Map.of("type", "string"),
                "candidatePhone", Map.of("type", "string")
            ),
            "required", List.of("jobTitle", "candidateName", "candidateEmail")
        );
    }

    @Override
    public boolean isWrite() {
        return true;
    }

    @Override
    public PermissionCode requiredPermission() {
        return PermissionCode.APPLICATION_CREATE;
    }

    @Override
    public String describeProposal(Map<String, Object> args) {
        return "refer " + args.get("candidateName") + " for the \"" + args.get("jobTitle") + "\" position";
    }

    @Override
    public AiToolResult execute(Map<String, Object> args, Long userId, Long companyId) {
        if (args == null || args.get("jobTitle") == null || args.get("candidateName") == null || args.get("candidateEmail") == null) {
            return AiToolResult.failure("I need the job title, the candidate's name, and their email to submit a referral.");
        }

        String jobTitle = args.get("jobTitle").toString().trim().toLowerCase();
        List<JobPosting> openPostings = jobPostingRepository.findByCompanyIdAndStatus(companyId, JobPostingStatus.OPEN);
        List<JobPosting> matches = openPostings.stream()
            .filter(p -> p.getTitle() != null && p.getTitle().toLowerCase().contains(jobTitle))
            .toList();

        if (matches.isEmpty()) {
            return AiToolResult.failure("I couldn't find an open position matching \"" + args.get("jobTitle") + "\".");
        }
        if (matches.size() > 1) {
            String titles = matches.stream().map(JobPosting::getTitle).reduce((a, b) -> a + "\", \"" + b).orElse("");
            return AiToolResult.failure("That matches more than one open position: \"" + titles + "\" - which one did you mean?");
        }

        JobPosting posting = matches.get(0);
        Long referringEmployeeId = employeeRepository.findByUserId(userId).map(e -> e.getId()).orElse(null);

        JobApplicationRequest request = new JobApplicationRequest();
        request.setApplicantName(args.get("candidateName").toString());
        request.setApplicantEmail(args.get("candidateEmail").toString());
        if (args.get("candidatePhone") != null) request.setApplicantPhone(args.get("candidatePhone").toString());
        request.setSource(ApplicationSource.EMPLOYEE_REFERRAL);
        request.setReferredByEmployeeId(referringEmployeeId);

        try {
            JobApplicationResponse response = recruitmentService.apply(posting.getId(), request);
            return AiToolResult.ok(
                "Referred " + request.getApplicantName() + " for \"" + posting.getTitle()
                    + "\" - application #" + response.getId() + " is now in the pipeline.",
                response);
        } catch (BadRequestException e) {
            return AiToolResult.failure("Couldn't submit that referral: " + e.getMessage());
        }
    }
}
