package com.zuhoocms.modules.ai.tool;

import com.zuhoocms.shared.exception.ApiException;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.Map;

/**
 * Runs one agent tool in its own REQUIRES_NEW transaction, turning the business exceptions its wrapped service throws into a friendly {@link AiToolResult#failure} rather than a 500 or a rollback of the whole turn.
 * A failed tool's writes are always rolled back: the callback marks rollback-only, which also stops UnexpectedRollbackException when an inner @Transactional service already marked it.
 */
@Slf4j
@Component
public class AiToolExecutor {

    private final TransactionTemplate requiresNew;

    public AiToolExecutor(PlatformTransactionManager transactionManager) {
        this.requiresNew = new TransactionTemplate(transactionManager);
        this.requiresNew.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public AiToolResult execute(AiTool tool, Map<String, Object> args, Long userId, Long companyId) {
        Map<String, Object> safeArgs = args != null ? args : Map.of();
        try {
            AiToolResult result = requiresNew.execute(status -> {
                try {
                    AiToolResult r = tool.execute(safeArgs, userId, companyId);
                    if (r == null || !r.isSuccess()) status.setRollbackOnly();
                    return r;
                } catch (RuntimeException e) {
                    status.setRollbackOnly();
                    return friendlyFailure(tool, e);
                }
            });
            return result != null ? result : AiToolResult.failure(genericFailure(tool));
        } catch (RuntimeException e) {
            // Commit-time failures (constraint violations flushed at commit, etc).
            return friendlyFailure(tool, e);
        }
    }

    private AiToolResult friendlyFailure(AiTool tool, RuntimeException e) {
        if (e instanceof BadRequestException || e instanceof ResourceNotFoundException) {
            log.info("AI tool {} refused: {}", tool.name(), e.getMessage());
            return AiToolResult.failure("I couldn't complete that: " + e.getMessage());
        }
        if (e instanceof ForbiddenException || e instanceof AccessDeniedException) {
            log.info("AI tool {} denied: {}", tool.name(), e.getMessage());
            return AiToolResult.failure("I couldn't complete that - your account isn't allowed to do it.");
        }
        if (e instanceof ApiException api && api.getStatus().is4xxClientError()) {
            log.info("AI tool {} refused ({}): {}", tool.name(), api.getStatus(), e.getMessage());
            return AiToolResult.failure("I couldn't complete that: " + e.getMessage());
        }
        log.warn("AI tool {} failed unexpectedly", tool.name(), e);
        return AiToolResult.failure(genericFailure(tool));
    }

    private static String genericFailure(AiTool tool) {
        return "Sorry, something went wrong while trying to do that - nothing was changed. "
            + "Please try again, or use the regular page for it.";
    }
}
