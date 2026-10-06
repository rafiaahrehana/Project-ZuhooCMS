package com.zuhoocms.modules.ai.tool.impl;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.ai.tool.AiTool;
import com.zuhoocms.modules.ai.tool.AiToolResult;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.performance.PerformanceReviewResponse;
import com.zuhoocms.modules.hrm.performance.PerformanceService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor
public class CheckPerformanceReviewTool implements AiTool {

    private final PerformanceService performanceService;
    private final EmployeeRepository employeeRepository;
    private final AuthorizationService authorizationService;

    @Override
    public String name() {
        return "check_performance_review";
    }

    @Override
    public String description() {
        return "Show the employee's most recent performance review - scores, strengths, areas for improvement.";
    }

    @Override
    public Map<String, Object> parametersSchema() {
        return Map.of("type", "object", "properties", Map.of());
    }

    @Override
    public boolean isWrite() {
        return false;
    }

    @Override
    public AiToolResult execute(Map<String, Object> args, Long userId, Long companyId) {
        Long employeeId = employeeRepository.findByUserId(userId).map(e -> e.getId()).orElse(null);
        if (employeeId == null) {
            return AiToolResult.failure("You don't have an employee profile set up, so there's no review to show.");
        }

        // An in-progress review is still the reviewers' draft; listForEmployee already hides those without PERFORMANCE_VIEW, and this filter applies the same rule to managers asking about themselves.
        List<PerformanceReviewResponse> reviews = performanceService
            .listForEmployee(employeeId, PageRequest.of(0, 20, Sort.by("createdAt").descending()))
            .getContent().stream()
            .filter(PerformanceReviewResponse::isFinalised)
            .toList();

        if (reviews.isEmpty()) {
            return AiToolResult.ok("You don't have any completed performance reviews on record yet.", List.of());
        }

        PerformanceReviewResponse r = reviews.get(0);
        // Salary increment and employment-status recommendations are management-only.
        if (!authorizationService.hasPermission(PermissionCode.PERFORMANCE_VIEW)) {
            r.setSalaryIncrement(null);
            r.setEmploymentStatusRecommendation(null);
        }
        StringBuilder sb = new StringBuilder("Your most recent performance review (");
        sb.append(r.getReviewPeriodStart()).append(" to ").append(r.getReviewPeriodEnd()).append("):\n");
        if (r.getOverallScore() != null) sb.append("- Overall score: ").append(r.getOverallScore()).append('\n');
        if (r.getPerformanceLevel() != null) sb.append("- Performance level: ").append(r.getPerformanceLevel()).append('\n');
        sb.append("- Stage: ").append(r.getStage()).append(r.isFinalised() ? " (finalised)" : " (not yet finalised)").append('\n');
        if (r.getStrengths() != null && !r.getStrengths().isBlank()) sb.append("- Strengths: ").append(r.getStrengths()).append('\n');
        if (r.getAreasForImprovement() != null && !r.getAreasForImprovement().isBlank()) sb.append("- Areas for improvement: ").append(r.getAreasForImprovement()).append('\n');
        if (r.getGoalsForNextPeriod() != null && !r.getGoalsForNextPeriod().isBlank()) sb.append("- Goals for next period: ").append(r.getGoalsForNextPeriod()).append('\n');

        return AiToolResult.ok(sb.toString(), r);
    }
}
