package com.zuhoocms.modules.hrm.recruitment.careerpage;

import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.enums.JobPostingStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.recruitment.ats.CvScoringService;
import com.zuhoocms.modules.hrm.recruitment.candidate.Candidate;
import com.zuhoocms.modules.hrm.recruitment.candidate.CandidateService;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPostingRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.storage.LocalFileStorageService;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** The PUBLIC careers page, unauthenticated: the slug is the only tenant key, every query is scoped through the CareerPageSettings row it resolves to, and only OPEN postings within deadline are exposed. */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/public/careers")
public class PublicCareersController {

    static final String APPLY_SUCCESS_MESSAGE = "Application received - we'll be in touch";

    private final CareerPageSettingsRepository settingsRepository;
    private final CompanyRepository companyRepository;
    private final JobPostingRepository jobPostingRepository;
    private final JobApplicationRepository applicationRepository;
    private final CandidateService candidateService;
    private final CvScoringService cvScoringService;
    private final LocalFileStorageService fileStorageService;

    @GetMapping("/{slug}")
    @Transactional(readOnly = true)
    public ResponseEntity<CareerPageView> page(@PathVariable String slug) {
        CareerPageSettings settings = requirePublished(slug);
        Company company = companyRepository.findById(settings.getCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Career page not found"));

        CareerPageView view = new CareerPageView();
        view.companyName = company.getCompanyName();
        view.headline = settings.getHeadline();
        view.about = settings.getAbout();
        view.brandColor = settings.getBrandColor();
        view.jobs = openPostings(settings.getCompanyId()).stream().map(JobCard::from).toList();
        return ResponseEntity.ok(view);
    }

    @GetMapping("/{slug}/jobs/{jobId}")
    @Transactional(readOnly = true)
    public ResponseEntity<JobDetail> job(@PathVariable String slug, @PathVariable Long jobId) {
        CareerPageSettings settings = requirePublished(slug);
        return ResponseEntity.ok(JobDetail.from(requireOpenPosting(settings, jobId)));
    }

    @PostMapping("/{slug}/jobs/{jobId}/apply")
    @Transactional
    public ResponseEntity<ApplyResult> apply(@PathVariable String slug, @PathVariable Long jobId,
                                             @RequestBody ApplyRequest request) {
        CareerPageSettings settings = requirePublished(slug);
        JobPosting posting = requireOpenPosting(settings, jobId);

        // Honeypot: real users never see this field, so bots that fill every input get a success response and no record.
        if (request.getWebsite() != null && !request.getWebsite().isBlank()) {
            return ResponseEntity.ok(new ApplyResult("Application received"));
        }

        String name = trimToNull(request.getApplicantName());
        // Lowercase to match RecruitmentServiceImpl.apply()'s duplicate check: "Jane@Gmail.com" vs "jane@gmail.com" bypassed the duplicate guard entirely here.
        String email = trimToNull(request.getApplicantEmail() != null ? request.getApplicantEmail().toLowerCase() : null);
        if (name == null || email == null) {
            throw new BadRequestException("Name and email are required");
        }
        if (!email.matches("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")) {
            throw new BadRequestException("Enter a valid email address");
        }

        // The public form always implies CAREER_PAGE: a client-supplied source is never trusted here, unlike staff-logged applications.
        String phone = trimToNull(request.getApplicantPhone());
        // Only a resume uploaded through this company's careers form, never an arbitrary external link.
        String resumeUrl = com.zuhoocms.shared.storage.FileReferencePolicy.requireOwnForCompany(
                trimToNull(request.getResumeUrl()), settings.getCompanyId());
        String linkedInUrl = trimToNull(request.getLinkedInUrl());
        String portfolioUrl = trimToNull(request.getPortfolioUrl());
        if (name.length() > 150 || (phone != null && phone.length() > 30) || email.length() > 200
                || (resumeUrl != null && resumeUrl.length() > 500) || (linkedInUrl != null && linkedInUrl.length() > 500)
                || (portfolioUrl != null && portfolioUrl.length() > 500)) {
            throw new BadRequestException("One of the fields is too long");
        }

        // Anonymous: the submitter proves nothing about owning the email, so an existing candidate's details are never refreshed from it (refreshExistingDetails=false).
        Candidate candidate = candidateService.findOrCreate(settings.getCompanyId(), name, email,
                phone, ApplicationSource.CAREER_PAGE, resumeUrl, linkedInUrl, portfolioUrl, false);

        // OFFER_REJECTED included alongside REJECTED/WITHDRAWN - see RecruitmentServiceImpl.apply()'s identical exclusion list.
        if (applicationRepository.existsByJobPostingIdAndCandidateIdAndStatusNotIn(posting.getId(), candidate.getId(),
                java.util.List.of(com.zuhoocms.enums.ApplicationStatus.REJECTED, com.zuhoocms.enums.ApplicationStatus.WITHDRAWN,
                        com.zuhoocms.enums.ApplicationStatus.OFFER_REJECTED))) {
            // Same 200 and message as a successful application: a distinct "already applied" answer let anyone probe whether an email is in the pipeline.
            return ResponseEntity.ok(new ApplyResult(APPLY_SUCCESS_MESSAGE));
        }

        Company companyRef = new Company();
        companyRef.setId(settings.getCompanyId());

        JobApplication application = JobApplication.builder()
                .jobPosting(posting)
                .company(companyRef)
                .candidate(candidate)
                .applicantName(name)
                .applicantPhone(phone)
                .resumeUrl(resumeUrl)
                .linkedInUrl(linkedInUrl)
                .portfolioUrl(portfolioUrl)
                .coverLetter(trimToNull(request.getCoverLetter()))
                .source(ApplicationSource.CAREER_PAGE)
                .status(ApplicationStatus.APPLIED)
                .build();
        applicationRepository.save(application);
        cvScoringService.scheduleAfterCommit(settings.getCompanyId(), application.getId());
        return ResponseEntity.ok(new ApplyResult(APPLY_SUCCESS_MESSAGE));
    }

    /** Anonymous resume upload for the public apply form, stored as a PRIVATE RESUME file of the career page's company; the returned /api/files/{id} URL is the only resumeUrl apply() accepts, and what ATS scoring reads (see CvScoringService). */
    @PostMapping("/{slug}/upload-resume")
    public ResponseEntity<Map<String, String>> uploadResume(@PathVariable String slug,
                                                              @RequestParam("file") MultipartFile file) {
        CareerPageSettings settings = requirePublished(slug);
        Map<String, String> response = new HashMap<>();
        // Resume-only store: PDF/DOC/DOCX by extension AND file signature, 10MB max; the general storeFile() accepted images, spreadsheets and SVG from anonymous visitors.
        response.put("fileUrl", fileStorageService.storeResume(file, settings.getCompanyId()));
        return ResponseEntity.ok(response);
    }

    private CareerPageSettings requirePublished(String slug) {
        return settingsRepository.findBySlugIgnoreCase(slug)
                .filter(CareerPageSettings::isPublished)
                .orElseThrow(() -> new ResourceNotFoundException("Career page not found"));
    }

    private List<JobPosting> openPostings(Long companyId) {
        return jobPostingRepository.findByCompanyIdAndStatus(companyId, JobPostingStatus.OPEN).stream()
                .filter(p -> p.getDeadline() == null || !p.getDeadline().isBefore(LocalDate.now()))
                .toList();
    }

    private JobPosting requireOpenPosting(CareerPageSettings settings, Long jobId) {
        JobPosting posting = jobPostingRepository.findByIdAndCompanyId(jobId, settings.getCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Job not found"));
        if (posting.getStatus() != JobPostingStatus.OPEN
                || (posting.getDeadline() != null && posting.getDeadline().isBefore(LocalDate.now()))) {
            throw new ResourceNotFoundException("This position is no longer open");
        }
        return posting;
    }

    private String trimToNull(String v) {
        if (v == null) return null;
        String trimmed = v.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    @Getter @Setter
    public static class CareerPageView {
        private String companyName;
        private String headline;
        private String about;
        private String brandColor;
        private List<JobCard> jobs;
    }

    /** The posting's department name, via loadable(): the lazy proxy is non-null and throws once the department is soft-deleted (BaseEntity's {@code @SQLRestriction}), which would 500 the public careers page. */
    private static String departmentName(JobPosting p) {
        var department = SoftDeletedProxies.loadable(p.getDepartment());
        return department != null ? department.getName() : null;
    }

    @Getter @Setter
    public static class JobCard {
        private Long id;
        private String title;
        private String location;
        private String employmentType;
        private boolean remote;
        private LocalDate deadline;
        private String departmentName;

        static JobCard from(JobPosting p) {
            JobCard c = new JobCard();
            c.id = p.getId();
            c.title = p.getTitle() != null ? p.getTitle() : p.getJobTitle();
            c.location = p.getLocation();
            c.employmentType = p.getEmploymentType() != null ? p.getEmploymentType().name() : null;
            c.remote = Boolean.TRUE.equals(p.getRemote());
            c.deadline = p.getDeadline();
            c.departmentName = departmentName(p);
            return c;
        }
    }

    @Getter @Setter
    public static class JobDetail extends JobCard {
        private String description;
        private String requirements;
        private String responsibilities;
        private BigDecimal salaryMin;
        private BigDecimal salaryMax;
        private Integer vacancies;

        static JobDetail from(JobPosting p) {
            JobDetail d = new JobDetail();
            d.setId(p.getId());
            d.setTitle(p.getTitle() != null ? p.getTitle() : p.getJobTitle());
            d.setLocation(p.getLocation());
            d.setEmploymentType(p.getEmploymentType() != null ? p.getEmploymentType().name() : null);
            d.setRemote(Boolean.TRUE.equals(p.getRemote()));
            d.setDeadline(p.getDeadline());
            d.setDepartmentName(departmentName(p));
            d.description = p.getDescription();
            d.requirements = p.getRequirements();
            d.responsibilities = p.getResponsibilities();
            d.salaryMin = p.getSalaryMin();
            d.salaryMax = p.getSalaryMax();
            d.vacancies = p.getVacancies();
            return d;
        }
    }

    @Getter @Setter
    public static class ApplyRequest {
        private String applicantName;
        private String applicantEmail;
        private String applicantPhone;
        private String resumeUrl;
        private String coverLetter;
        private String linkedInUrl;
        private String portfolioUrl;
        /** Honeypot - must stay empty. */
        private String website;
    }

    public record ApplyResult(String message) {}
}
