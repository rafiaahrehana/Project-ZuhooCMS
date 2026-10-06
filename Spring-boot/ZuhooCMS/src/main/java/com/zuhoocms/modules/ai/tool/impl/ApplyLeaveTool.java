package com.zuhoocms.modules.ai.tool.impl;

import com.zuhoocms.enums.LeaveType;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.modules.ai.tool.AiTool;
import com.zuhoocms.modules.ai.tool.AiToolResult;
import com.zuhoocms.modules.ai.tool.AiToolValidator;
import com.zuhoocms.modules.hrm.leave.LeaveService;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestDto;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestResponse;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.Map;

/** Write tool with no confirmation logic of its own: the gate lives once in AiServiceImpl#runAgentTurn, which only executes after an explicit confirmation. */
@Component
@RequiredArgsConstructor
public class ApplyLeaveTool implements AiTool {

    private final LeaveService leaveService;
    private final AiToolValidator validator;

    @Override
    public String name() {
        return "apply_leave";
    }

    @Override
    public String description() {
        return "Submit a leave request for the employee. Does not approve it - goes to the normal approval queue like applying from the Leave Requests page.";
    }

    @Override
    public Map<String, Object> parametersSchema() {
        return Map.of(
            "type", "object",
            "properties", Map.of(
                "leaveType", Map.of("type", "string", "enum",
                    java.util.Arrays.stream(LeaveType.values()).map(Enum::name).toList(),
                    "description", "One of: " + java.util.Arrays.toString(LeaveType.values())),
                "startDate", Map.of("type", "string", "format", "date"),
                "endDate", Map.of("type", "string", "format", "date"),
                "reason", Map.of("type", "string")
            ),
            "required", java.util.List.of("leaveType", "startDate", "endDate")
        );
    }

    // The Leave Requests page's own permission; without it the tool is not offered to the model and is refused if named anyway.
    @Override
    public PermissionCode requiredPermission() {
        return PermissionCode.LEAVE_CREATE;
    }

    @Override
    public boolean isWrite() {
        return true;
    }

    @Override
    public String describeProposal(Map<String, Object> args) {
        String reason = args.get("reason") != null ? " (\"" + args.get("reason") + "\")" : "";
        return "submit " + args.get("leaveType") + " leave from " + args.get("startDate")
            + " to " + args.get("endDate") + reason;
    }

    @Override
    public AiToolResult execute(Map<String, Object> args, Long userId, Long companyId) {
        if (args == null || args.get("leaveType") == null
                || args.get("startDate") == null || args.get("endDate") == null) {
            return AiToolResult.failure("Missing leave type, start date, or end date.");
        }

        LeaveRequestDto dto = new LeaveRequestDto();
        try {
            dto.setLeaveType(LeaveType.valueOf(args.get("leaveType").toString().toUpperCase()));
            dto.setStartDate(LocalDate.parse(args.get("startDate").toString()));
            dto.setEndDate(LocalDate.parse(args.get("endDate").toString()));
        } catch (Exception e) {
            return AiToolResult.failure("Couldn't understand the leave type or dates: " + e.getMessage());
        }
        Object reason = args.get("reason");
        if (reason != null) dto.setReason(reason.toString());

        try {
            // apply() resolves the employee from SecurityUtil and enforces balance, overlap, no-backdating and policy rules exactly as the Leave Requests page does.
            String invalid = validator.problems(dto);
            if (invalid != null) {
                return AiToolResult.failure("That doesn't look right - " + invalid + ".");
            }
            LeaveRequestResponse response = leaveService.apply(dto);
            return AiToolResult.ok(
                "Submitted: " + dto.getLeaveType() + " leave from " + dto.getStartDate()
                    + " to " + dto.getEndDate() + ", now pending approval (request #"
                    + response.getId() + ").",
                response);
        } catch (BadRequestException e) {
            return AiToolResult.failure("Couldn't submit that leave request: " + e.getMessage());
        }
    }
}
