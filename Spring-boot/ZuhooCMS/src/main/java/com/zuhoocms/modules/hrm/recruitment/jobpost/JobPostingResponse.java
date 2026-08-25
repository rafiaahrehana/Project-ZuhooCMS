package com.zuhoocms.modules.hrm.recruitment.jobpost;

import com.zuhoocms.enums.EducationLevel;
import com.zuhoocms.enums.EmploymentType;
import com.zuhoocms.enums.JobPostingStatus;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Setter
public class JobPostingResponse {
    private Long id;
    private String title;
    private String jobTitle;
    private String description;
    private String requirements;
    private String responsibilities;
    private String location;
    private EmploymentType employmentType;
    private JobPostingStatus status;
    private int vacancies;
    private BigDecimal salaryMin;
    private BigDecimal salaryMax;
    private LocalDate deadline;
    private boolean remote;
    private Long departmentId;
    private String departmentName;
    private Long createdById;
    private String createdByName;
    private Long assignedRecruiterId;
    private String assignedRecruiterName;
    private String requiredSkills;
    private String preferredSkills;
    private Integer minExperienceYears;
    private EducationLevel minEducationLevel;
    private LocalDateTime createdAt;
}
