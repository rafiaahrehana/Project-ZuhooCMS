package com.zuhoocms.modules.hrm.performance;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.time.LocalDate;

@Data
public class PerformanceReviewRequest {
    /** Validation group for create only - an edit (PATCH) may omit these. */
    public interface OnCreate {}

    @NotNull(message = "Employee ID is required", groups = OnCreate.class)
    private Long employeeId;
    @NotNull(message = "Review period start is required", groups = OnCreate.class)
    private LocalDate reviewPeriodStart;
    @NotNull(message = "Review period end is required", groups = OnCreate.class)
    private LocalDate reviewPeriodEnd;
    @Min(1) @Max(10)
    private Integer scoreWorkQuality;
    @Min(1) @Max(10)
    private Integer scoreProductivity;
    @Min(1) @Max(10)
    private Integer scoreCommunication;
    @Min(1) @Max(10)
    private Integer scoreTeamwork;
    @Min(1) @Max(10)
    private Integer scoreInitiative;
    @Min(1) @Max(10)
    private Integer scorePunctuality;
    // Competencies are 1-10, matching the form label; they were validated @Max(5), so any score above 5 was rejected.
    @Min(1) @Max(10)
    private Integer scoreLeadership;
    @Min(1) @Max(10)
    private Integer scoreProblemSolving;
    @Min(1) @Max(10)
    private Integer scoreInnovation;

    private String strengths;
    private String areasForImprovement;
    private String goalsForNextPeriod;
    private String comments;

    private String performanceLevel;
    private String promotionRecommendation;
    private String promotionReadiness;
    private String salaryIncrement;
    private String employmentStatusRecommendation;
    @Min(0) @Max(100)
    private Integer goalCompletionPercent;
    /** Comma-separated training topics. */
    private String trainingRecommendation;
    /** Comma-separated recognition awards. */
    private String recognition;
    /** JSON array of {title, progress} for the goal-tracking bars. */
    private String goals;

    @com.fasterxml.jackson.annotation.JsonIgnore
    @jakarta.validation.constraints.AssertTrue(message = "Review period end must be on or after the start")
    public boolean isReviewPeriodValid() {
        return reviewPeriodStart == null || reviewPeriodEnd == null || !reviewPeriodEnd.isBefore(reviewPeriodStart);
    }
}
