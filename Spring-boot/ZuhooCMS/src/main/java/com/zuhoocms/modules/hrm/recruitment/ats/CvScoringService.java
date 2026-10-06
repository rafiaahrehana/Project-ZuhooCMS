package com.zuhoocms.modules.hrm.recruitment.ats;

import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.AtsParseStatus;
import com.zuhoocms.enums.EducationLevel;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Automated ATS match score for a resume stored by this system's own upload endpoints: only reads local disk under file.upload-dir, never fetches a candidate-supplied URL that could point at an internal address.
 * A signal only (see JobApplication's ats* fields) - it never gates a status transition, auto-rejects, or affects the recruiter's manual Evaluate score.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CvScoringService {

    // Required Skills 40 / Experience 25 / Education 15 / Preferred Skills & Certifications 20, renormalized below over whichever categories the posting defined.
    private static final double WEIGHT_REQUIRED_SKILLS = 0.40;
    private static final double WEIGHT_EXPERIENCE = 0.25;
    private static final double WEIGHT_EDUCATION = 0.15;
    private static final double WEIGHT_PREFERRED_SKILLS = 0.20;

    private static final Pattern EXPERIENCE_YEARS_PATTERN =
        Pattern.compile("(\\d{1,2})\\+?\\s*(?:years?|yrs?)", Pattern.CASE_INSENSITIVE);

    // Checked in this order (highest first) - the first level whose keywords appear anywhere wins.
    // Short abbreviations (m.a, b.sc, ...) require the period(s): bare "MA"/"BA" collide with US state codes too often; full words stay period-optional.
    private static final Map<EducationLevel, Pattern> EDUCATION_KEYWORDS = new LinkedHashMap<>();
    static {
        EDUCATION_KEYWORDS.put(EducationLevel.PHD, Pattern.compile("\\b(ph\\.?d|doctorate)\\b", Pattern.CASE_INSENSITIVE));
        EDUCATION_KEYWORDS.put(EducationLevel.MASTER, Pattern.compile("\\b(master'?s?|m\\.sc|m\\.a\\.?|mba|m\\.eng)\\b", Pattern.CASE_INSENSITIVE));
        EDUCATION_KEYWORDS.put(EducationLevel.BACHELOR, Pattern.compile("\\b(bachelor'?s?|b\\.sc|b\\.a\\.?|b\\.eng|b\\.tech)\\b", Pattern.CASE_INSENSITIVE));
        EDUCATION_KEYWORDS.put(EducationLevel.DIPLOMA, Pattern.compile("\\bdiploma\\b", Pattern.CASE_INSENSITIVE));
    }

    private final JobApplicationRepository applicationRepository;
    private final CvTextExtractor textExtractor;

    // Self-injected lazily so the afterCommit callback calls scoreApplication() THROUGH the Spring proxy: a bare `this.` self-invocation silently skips @Async and @Transactional.
    @Autowired
    @Lazy
    private CvScoringService self;

    // Resolves both stored-file URLs (/api/files/{id}) and legacy /uploads/ names to local disk.
    @Autowired
    @Lazy
    private com.zuhoocms.shared.storage.LocalFileStorageService fileStorage;

    @Value("${file.upload-dir:uploads}")
    private String uploadDir;

    /** Called by both apply() entry points right after save(); defers to afterCommit synchronization because the @Async scoring would otherwise look the row up before this transaction commits. */
    public void scheduleAfterCommit(Long companyId, Long applicationId) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    self.scoreApplication(companyId, applicationId);
                }
            });
        } else {
            self.scoreApplication(companyId, applicationId);
        }
    }

    /**
     * companyId travels as a parameter rather than via SecurityUtil because this runs on a separate thread with no security context propagated to it.
     *
     * Not transactional itself: scoring runs in {@link #scoreInTransaction}, and a throw (including at commit, which a try/catch inside the transaction can never see) marks the application FAILED in a fresh transaction rather than leaving it PENDING forever.
     */
    @Async
    public void scoreApplication(Long companyId, Long applicationId) {
        try {
            self.scoreInTransaction(companyId, applicationId);
        } catch (Exception ex) {
            log.warn("ATS scoring failed for application {} - marking FAILED", applicationId, ex);
            try {
                self.markFailed(companyId, applicationId);
            } catch (Exception inner) {
                log.error("Could not mark application {} as ATS FAILED", applicationId, inner);
            }
        }
    }

    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.REQUIRES_NEW)
    public void markFailed(Long companyId, Long applicationId) {
        applicationRepository.findByIdAndCompanyId(applicationId, companyId).ifPresent(application -> {
            application.setAtsParseStatus(AtsParseStatus.FAILED);
            application.setAtsParsedAt(Instant.now());
        });
    }

    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.REQUIRES_NEW)
    public void scoreInTransaction(Long companyId, Long applicationId) {
        JobApplication application = applicationRepository.findByIdAndCompanyId(applicationId, companyId).orElse(null);
        if (application == null) {
            log.warn("ATS scoring skipped - application {} not found for company {}", applicationId, companyId);
            return;
        }

        // loadable(), not a null check: a proxy to a soft-deleted posting/candidate is non-null and throws when read.
        JobPosting posting = SoftDeletedProxies.loadable(application.getJobPosting());
        if (posting == null || !hasAnyRequirement(posting)) {
            application.setAtsParseStatus(AtsParseStatus.NOT_APPLICABLE);
            application.setAtsParsedAt(Instant.now());
            return;
        }

        var candidate = SoftDeletedProxies.loadable(application.getCandidate());
        String resumeUrl = application.getResumeUrl() != null ? application.getResumeUrl()
            : candidate != null ? candidate.getResumeUrl() : null;
        java.util.Optional<com.zuhoocms.shared.storage.LocalFileStorageService.LocalFile> local =
                resumeUrl == null ? java.util.Optional.empty() : fileStorage.resolveLocal(resumeUrl);
        Path localPath = local.map(com.zuhoocms.shared.storage.LocalFileStorageService.LocalFile::path).orElse(null);
        if (localPath == null || !Files.isRegularFile(localPath)) {
            application.setAtsParseStatus(AtsParseStatus.NO_RESUME);
            application.setAtsParsedAt(Instant.now());
            return;
        }

        try {
            byte[] bytes = Files.readAllBytes(localPath);
            String text = textExtractor.extract(bytes, "." + local.get().extension());
            applyScoring(application, posting, text);
            application.setAtsParseStatus(AtsParseStatus.SUCCESS);
        } catch (UnsupportedResumeFormatException ex) {
            application.setAtsParseStatus(AtsParseStatus.UNSUPPORTED_FORMAT);
        } catch (Exception ex) {
            log.warn("ATS scoring failed for application {}", applicationId, ex);
            application.setAtsParseStatus(AtsParseStatus.FAILED);
        }
        application.setAtsParsedAt(Instant.now());
    }

    private void applyScoring(JobApplication application, JobPosting posting, String text) {
        String lower = text.toLowerCase();

        List<String> requiredSkills = splitSkills(posting.getRequiredSkills());
        List<String> preferredSkills = splitSkills(posting.getPreferredSkills());

        List<String> matchedRequired = new ArrayList<>();
        List<String> missingRequired = new ArrayList<>();
        for (String skill : requiredSkills) {
            (containsSkill(lower, skill) ? matchedRequired : missingRequired).add(skill);
        }
        List<String> matchedPreferred = new ArrayList<>();
        for (String skill : preferredSkills) {
            if (containsSkill(lower, skill)) matchedPreferred.add(skill);
        }

        Integer extractedYears = extractMaxYears(text);
        EducationLevel extractedLevel = extractEducationLevel(text);

        application.setAtsMatchedRequiredSkills(join(matchedRequired));
        application.setAtsMissingRequiredSkills(join(missingRequired));
        application.setAtsMatchedPreferredSkills(join(matchedPreferred));
        application.setAtsExtractedExperienceYears(extractedYears);

        double weightedSum = 0;
        double totalWeight = 0;

        if (!requiredSkills.isEmpty()) {
            double score = (double) matchedRequired.size() / requiredSkills.size();
            weightedSum += WEIGHT_REQUIRED_SKILLS * score;
            totalWeight += WEIGHT_REQUIRED_SKILLS;
        }
        if (posting.getMinExperienceYears() != null) {
            // minExperienceYears == 0 means no floor: dividing by it would produce NaN and silently zero the whole atsScore.
            double score = posting.getMinExperienceYears() <= 0 ? 1.0
                : extractedYears == null ? 0.0
                : Math.min(1.0, extractedYears / (double) posting.getMinExperienceYears());
            weightedSum += WEIGHT_EXPERIENCE * score;
            totalWeight += WEIGHT_EXPERIENCE;
        }
        if (posting.getMinEducationLevel() != null) {
            boolean meets = extractedLevel != null && extractedLevel.ordinal() >= posting.getMinEducationLevel().ordinal();
            application.setAtsMeetsEducationRequirement(meets);
            weightedSum += WEIGHT_EDUCATION * (meets ? 1.0 : 0.0);
            totalWeight += WEIGHT_EDUCATION;
        } else {
            application.setAtsMeetsEducationRequirement(null);
        }
        if (!preferredSkills.isEmpty()) {
            double score = (double) matchedPreferred.size() / preferredSkills.size();
            weightedSum += WEIGHT_PREFERRED_SKILLS * score;
            totalWeight += WEIGHT_PREFERRED_SKILLS;
        }

        application.setAtsScore(totalWeight > 0 ? (int) Math.round((weightedSum / totalWeight) * 100) : null);
    }

    /** Word-boundary match where the skill's edges are alphanumeric; plain substring otherwise (covers "C++", "C#", ".NET"). */
    private boolean containsSkill(String lowerText, String skill) {
        String needle = skill.trim().toLowerCase();
        if (needle.isEmpty()) return false;
        boolean startsWord = Character.isLetterOrDigit(needle.charAt(0));
        boolean endsWord = Character.isLetterOrDigit(needle.charAt(needle.length() - 1));
        // \b treats a letter-to-symbol transition as a boundary, so "C" would match inside "C++"/"C#", which are different technologies.
        String right = endsWord ? "\\b(?![+#])" : "";
        String pattern = (startsWord ? "\\b" : "") + Pattern.quote(needle) + right;
        return Pattern.compile(pattern).matcher(lowerText).find();
    }

    private Integer extractMaxYears(String text) {
        Matcher m = EXPERIENCE_YEARS_PATTERN.matcher(text);
        Integer max = null;
        while (m.find()) {
            int value = Integer.parseInt(m.group(1));
            if (max == null || value > max) max = value;
        }
        return max;
    }

    private EducationLevel extractEducationLevel(String text) {
        for (Map.Entry<EducationLevel, Pattern> entry : EDUCATION_KEYWORDS.entrySet()) {
            if (entry.getValue().matcher(text).find()) return entry.getKey();
        }
        return null;
    }

    private List<String> splitSkills(String csv) {
        if (csv == null || csv.isBlank()) return List.of();
        return Arrays.stream(csv.split(","))
            .map(String::trim)
            .filter(s -> !s.isEmpty())
            .toList();
    }

    /** Matches the @Column(length = 500) of the three ats*Skills columns on JobApplication. */
    private static final int SKILL_COLUMN_LENGTH = 500;

    /** Joined skill list truncated at a whole skill: a long list overflowed VARCHAR(500) at commit and rolled back the scoring. */
    private String join(List<String> values) {
        if (values.isEmpty()) return null;
        String joined = String.join(", ", values);
        if (joined.length() <= SKILL_COLUMN_LENGTH) return joined;
        String suffix = ", ...";
        String cut = joined.substring(0, SKILL_COLUMN_LENGTH - suffix.length());
        int lastSeparator = cut.lastIndexOf(", ");
        return (lastSeparator > 0 ? cut.substring(0, lastSeparator) : cut) + suffix;
    }

    private boolean hasAnyRequirement(JobPosting posting) {
        return notBlank(posting.getRequiredSkills()) || notBlank(posting.getPreferredSkills())
            || posting.getMinExperienceYears() != null || posting.getMinEducationLevel() != null;
    }

    private boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    /** Never issues a network request: reads local disk from the URL's filename segment (same path-traversal guard as LocalFileStorageService.persist()); an external link resolves to null, as with no resume. */
    private Path resolveOwnUploadPath(String resumeUrl) {
        if (resumeUrl == null || !resumeUrl.contains("/uploads/")) return null;
        String filename = resumeUrl.substring(resumeUrl.lastIndexOf('/') + 1);
        if (filename.isBlank()) return null;
        try {
            Path uploadPath = Paths.get(uploadDir).toAbsolutePath().normalize();
            Path target = uploadPath.resolve(filename).normalize();
            if (!target.startsWith(uploadPath)) return null;
            return target;
        } catch (java.nio.file.InvalidPathException ex) {
            // resumeUrl is free text, and a filesystem-illegal filename segment threw uncaught here, rolling back before atsParseStatus was set and leaving the application at PENDING forever.
            return null;
        }
    }

    private String extensionOf(String filename) {
        int idx = filename.lastIndexOf('.');
        return idx >= 0 ? filename.substring(idx).toLowerCase() : "";
    }
}
