package com.zuhoocms.modules.ai.tool;

import com.zuhoocms.auth.role.enums.PermissionCode;

import java.util.Map;

/**
 * One action the AI agent can take on an employee's behalf; a tool adds no new capability, only a natural-language front door to an existing SecurityUtil-scoped service method.
 * Non-negotiable: {@link #execute} must resolve what to act on only from the userId/companyId parameters, never from an id inside {@code args}.
 */
public interface AiTool {

    /** Stable, model-facing identifier, e.g. "check_leave_balance". Never renamed once shipped. */
    String name();

    /** One or two sentences the model uses to decide when this tool applies. */
    String description();

    /** JSON-Schema-shaped argument description, translated per-provider by each AiHttpClient's callWithTools(). */
    Map<String, Object> parametersSchema();

    /** True for anything that changes real data; mainly logging/UI labeling, since AiServiceImpl#runAgentTurn never executes a write tool on the first pass anyway. */
    boolean isWrite();

    /** Null when any authenticated employee may use this tool; otherwise AiToolRegistry#availableFor keeps it out of what is sent to the model. */
    default PermissionCode requiredPermission() {
        return null;
    }

    /** True when output carries third-party text (announcement bodies, client-written titles); the agent loop then fences it as untrusted data against prompt injection. */
    default boolean returnsUntrustedContent() {
        return false;
    }

    /** The confirm/cancel proposal shown before a write tool runs; override where the generic "run name with {args}" reads worse than a real sentence. */
    default String describeProposal(Map<String, Object> args) {
        return "run " + name() + " with " + args;
    }

    /** userId/companyId are always the real authenticated caller: implementations must use them exclusively, never an id parsed out of {@code args}. */
    AiToolResult execute(Map<String, Object> args, Long userId, Long companyId);
}
