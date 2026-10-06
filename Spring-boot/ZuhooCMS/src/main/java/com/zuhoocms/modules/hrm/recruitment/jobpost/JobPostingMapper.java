package com.zuhoocms.modules.hrm.recruitment.jobpost;

import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.modules.hrm.department.Department;
import com.zuhoocms.modules.hrm.employee.EmployeeUserResolver;
import org.springframework.stereotype.Component;

@Component
public class JobPostingMapper {
    public static JobPostingResponse toResponse(JobPosting j) {
        // Through SoftDeletedProxies: department, creator and recruiter are lazy proxies over soft-deletable rows and
        // throw EntityNotFoundException when touched (BaseEntity's @SQLRestriction), so a terminated recruiter or
        // creator 500'd the whole job list. Ids still come off the FK; only the display name is lost.
        Department dept = SoftDeletedProxies.loadable(j.getDepartment());
        JobPostingResponse r = new JobPostingResponse();
        r.setId(j.getId());
        r.setTitle(j.getTitle());
        r.setJobTitle(j.getJobTitle());
        r.setDescription(j.getDescription());
        r.setRequirements(j.getRequirements());
        r.setEmploymentType(j.getEmploymentType());
        r.setStatus(j.getStatus());
        r.setVacancies(j.getVacancies());
        r.setSalaryMin(j.getSalaryMin());
        r.setSalaryMax(j.getSalaryMax());
        r.setDeadline(j.getDeadline());
        r.setRemote(j.getRemote());
        r.setResponsibilities(j.getResponsibilities());
        r.setLocation(j.getLocation());
        r.setDepartmentId(SoftDeletedProxies.id(j.getDepartment()));
        r.setDepartmentName(dept != null ? dept.getName() : null);
        r.setCreatedById(SoftDeletedProxies.id(j.getCreatedBy()));
        r.setCreatedByName(EmployeeUserResolver.displayName(j.getCreatedBy()));
        r.setAssignedRecruiterId(SoftDeletedProxies.id(j.getAssignedRecruiter()));
        r.setAssignedRecruiterName(EmployeeUserResolver.displayName(j.getAssignedRecruiter()));
        r.setRequiredSkills(j.getRequiredSkills());
        r.setPreferredSkills(j.getPreferredSkills());
        r.setMinExperienceYears(j.getMinExperienceYears());
        r.setMinEducationLevel(j.getMinEducationLevel());
        r.setCreatedAt(j.getCreatedAt());
        return r;
    }
}
