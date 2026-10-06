package com.zuhoocms.core.interceptor;

import com.zuhoocms.shared.exception.BadRequestException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Bounds the raw {@code ?page=} and {@code ?size=} query parameters before any handler runs, so pure caller input
 * cannot reach {@code PageRequest.of} with values that blow up deeper in the stack.
 *
 * <p>Why here and not in each controller: {@code ?page=2147483647&size=1000} overflowed {@code page * size} inside
 * Spring Data's {@code PageableUtils.getOffsetAsInteger}, which threw {@code InvalidDataAccessApiUsageException} and
 * surfaced as a 500 on <i>every</i> paged endpoint. Sixty-odd controllers build their own
 * {@code PageRequest.of(page, size)} from {@code @RequestParam int}s, so there is no single binder to fix; an
 * interceptor on {@code /api/**} is the one place that sees the parameters for all of them, including the handful that
 * take a {@code Pageable} argument. Catching {@code InvalidDataAccessApiUsageException} in the exception handler was
 * rejected deliberately: that type also covers genuine internal misuse of the persistence API, which must stay a 500.
 *
 * <p>Only the upper bound lives here. A negative {@code page} or a zero/negative {@code size} already answers 400
 * through {@code PageRequest.of}'s own {@code IllegalArgumentException} and {@code GlobalExceptionHandler}, with a
 * better message than this class could invent.
 */
@Component
public class PaginationBoundsInterceptor implements HandlerInterceptor {

    /**
     * Sits above every per-controller cap (the largest is 100) and at the largest page size any client actually asks
     * for, so this never narrows a legitimate request - it only rejects nonsense.
     */
    public static final int MAX_PAGE_SIZE = 1000;

    /**
     * {@code MAX_PAGE_INDEX * MAX_PAGE_SIZE} is 10^8, two orders of magnitude below {@code Integer.MAX_VALUE}, so the
     * offset arithmetic Spring Data does on these two numbers can no longer overflow.
     */
    public static final int MAX_PAGE_INDEX = 100_000;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        rejectAbove(request.getParameter("page"), MAX_PAGE_INDEX, "page");
        rejectAbove(request.getParameter("size"), MAX_PAGE_SIZE, "size");
        return true;
    }

    private static void rejectAbove(String raw, int max, String name) {
        if (raw == null || raw.isBlank()) {
            return;
        }
        long value;
        try {
            value = Long.parseLong(raw.trim());
        } catch (NumberFormatException ex) {
            // Not a number at all (or wider than a long): Spring's own parameter conversion answers 400 for it.
            return;
        }
        if (value > max) {
            throw new BadRequestException("Parameter '" + name + "' must not be greater than " + max);
        }
    }
}
