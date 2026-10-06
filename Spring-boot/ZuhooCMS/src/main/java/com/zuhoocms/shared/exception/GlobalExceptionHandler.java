package com.zuhoocms.shared.exception;

import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;
import java.util.stream.Collectors;

@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    /**
     * Every error body leaves here with an explicit {@code Content-Type: application/json}.
     *
     * <p>Without it the body goes through content negotiation, and a client that sent e.g.
     * {@code Accept: application/xml} has no acceptable representation (there is no XML converter on the classpath),
     * so {@code HttpMediaTypeNotAcceptableException} was thrown <em>inside</em> this handler. That aborts
     * @ExceptionHandler resolution, the original exception escapes the DispatcherServlet, Tomcat turns it into a 500
     * ERROR dispatch to {@code /error}, and Spring Security answered that with a 401 - hiding a 404/400 behind a
     * misleading status. Presetting a concrete content type makes {@code AbstractMessageConverterMethodProcessor}
     * skip negotiation entirely, so the caller keeps the real status and a readable body. Sending JSON to a client
     * that asked for XML is deliberate: an error is more useful than an empty 406.
     */
    private static ResponseEntity<ApiResponse<Void>> json(HttpStatusCode status, String message) {
        return ResponseEntity.status(status)
            .contentType(MediaType.APPLICATION_JSON)
            .body(ApiResponse.error(message));
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNotFound(ResourceNotFoundException ex) {
        return json(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(DuplicateResourceException.class)
    public ResponseEntity<ApiResponse<Void>> handleDuplicate(DuplicateResourceException ex) {
        return json(HttpStatus.CONFLICT, ex.getMessage());
    }

    @ExceptionHandler(BadRequestException.class)
    public ResponseEntity<ApiResponse<Void>> handleBadRequest(BadRequestException ex) {
        return json(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(ForbiddenException.class)
    public ResponseEntity<ApiResponse<Void>> handleForbidden(ForbiddenException ex) {
        return json(HttpStatus.FORBIDDEN, ex.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalArgument(IllegalArgumentException ex) {
        return json(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiResponse<Void>> handleAccessDenied(AccessDeniedException ex) {
        return json(HttpStatus.FORBIDDEN, "You do not have permission to perform this action");
    }

    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<ApiResponse<Void>> handleBadCredentials(BadCredentialsException ex) {
        return json(HttpStatus.UNAUTHORIZED, "Invalid email or password");
    }

    @ExceptionHandler(org.springframework.security.authentication.LockedException.class)
    public ResponseEntity<ApiResponse<Void>> handleLocked(org.springframework.security.authentication.LockedException ex) {
        return json(HttpStatus.FORBIDDEN, "Account is locked or not yet activated");
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnauthorized(UnauthorizedException ex) {
        return json(HttpStatus.UNAUTHORIZED, ex.getMessage());
    }

    // Handles unverified users trying to log in
    @ExceptionHandler(DisabledException.class)
    public ResponseEntity<ApiResponse<Void>> handleDisabled(DisabledException ex) {
        return json(HttpStatus.FORBIDDEN,
            "Your email address has not been verified. Please check your inbox or requeststatus a new capture link.");
    }

    /** AI provider failures: provider error bodies, URLs and quota info go to the log only; the client always gets the same generic 503 text. */
    @ExceptionHandler(com.zuhoocms.modules.ai.exception.AiProviderException.class)
    public ResponseEntity<ApiResponse<Void>> handleAiProvider(
            com.zuhoocms.modules.ai.exception.AiProviderException ex) {
        if (!com.zuhoocms.modules.ai.exception.AiProviderException.USER_MESSAGE.equals(ex.getMessage())) {
            log.warn("AI provider failure: {}", ex.getMessage());
        }
        return json(HttpStatus.SERVICE_UNAVAILABLE,
            com.zuhoocms.modules.ai.exception.AiProviderException.USER_MESSAGE);
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiResponse<Void>> handleApiException(ApiException ex) {
        return json(ex.getStatus(), ex.getMessage());
    }

    /** @Version conflict (see ClientInvoice.version): the loser must retry against fresh data, so this must not fall through to the generic 500. */
    @ExceptionHandler(org.springframework.dao.OptimisticLockingFailureException.class)
    public ResponseEntity<ApiResponse<Void>> handleOptimisticLock(
            org.springframework.dao.OptimisticLockingFailureException ex) {
        log.warn("Optimistic lock conflict: {}", ex.getMessage());
        return json(HttpStatus.CONFLICT,
            "This record was just updated by someone else. Please refresh and try again.");
    }

    /** DB constraint violations that slip past app-level checks, e.g. a soft-deleted row still holding a unique index; otherwise a raw 500. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleDataIntegrityViolation(DataIntegrityViolationException ex) {
        log.warn("Data integrity violation: {}", ex.getMessage());
        return json(HttpStatus.CONFLICT,
            "This action conflicts with existing data (e.g. a duplicate name or code). Please use a different value.");
    }

    /** A blank/invalid enum-typed field fails Jackson before @Valid runs, so it never reaches MethodArgumentNotValidException and fell through as a 500. */
    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnreadableMessage(
            org.springframework.http.converter.HttpMessageNotReadableException ex) {
        log.warn("Malformed request body: {}", ex.getMessage());
        return json(HttpStatus.BAD_REQUEST, "Please check that all required fields have a valid value.");
    }

    /** Unconvertible path/query parameter, usually an enum: Spring's own message leaks the domain package and class names, so this answers with the accepted values instead. */
    @ExceptionHandler(org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Void>> handleTypeMismatch(
            org.springframework.web.method.annotation.MethodArgumentTypeMismatchException ex) {
        log.warn("Unconvertible request value for '{}'", ex.getName());

        Class<?> required = ex.getRequiredType();
        String detail = required != null && required.isEnum()
                ? " Valid values: " + String.join(", ",
                        java.util.Arrays.stream(required.getEnumConstants()).map(Object::toString).toList()) + "."
                : "";

        return json(HttpStatus.BAD_REQUEST, "'" + ex.getName() + "' has an invalid value." + detail);
    }

    /** Unknown sort/filter property (e.g. ?sortBy=password): as a 500 vs 200 it told the caller whether that property exists; backstop for endpoints not covered by CrmSortWhitelist. */
    @ExceptionHandler(org.springframework.data.core.PropertyReferenceException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnknownProperty(
            org.springframework.data.core.PropertyReferenceException ex) {
        log.warn("Unknown sort/filter property requested: {}", ex.getPropertyName());
        return json(HttpStatus.BAD_REQUEST,
            "'" + ex.getPropertyName() + "' is not a field you can sort or filter by.");
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Map<String, String>>> handleValidation(
            MethodArgumentNotValidException ex) {
        Map<String, String> errors = ex.getBindingResult().getFieldErrors().stream()
            .collect(Collectors.toMap(FieldError::getField,
                FieldError::getDefaultMessage, (a, b) -> a));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
            .contentType(MediaType.APPLICATION_JSON)
            .body(ApiResponse.error("Validation failed", errors));
    }

    /** A required query parameter / multipart part (e.g. {@code file}) is missing: the caller's fault. */
    @ExceptionHandler({
        org.springframework.web.bind.MissingServletRequestParameterException.class,
        org.springframework.web.multipart.support.MissingServletRequestPartException.class,
        org.springframework.web.multipart.MultipartException.class
    })
    public ResponseEntity<ApiResponse<Void>> handleMissingPart(Exception ex) {
        if (ex instanceof org.springframework.web.multipart.MaxUploadSizeExceededException tooBig) {
            return handleTooLarge(tooBig);
        }
        String name = null;
        if (ex instanceof org.springframework.web.bind.MissingServletRequestParameterException p) {
            name = p.getParameterName();
        } else if (ex instanceof org.springframework.web.multipart.support.MissingServletRequestPartException p) {
            name = p.getRequestPartName();
        }
        log.debug("Bad request shape: {}", ex.getMessage());
        return json(HttpStatus.BAD_REQUEST, name != null
            ? "Required parameter '" + name + "' is missing."
            : "The request is not a valid multipart upload.");
    }

    @ExceptionHandler(org.springframework.web.multipart.MaxUploadSizeExceededException.class)
    public ResponseEntity<ApiResponse<Void>> handleTooLarge(
            org.springframework.web.multipart.MaxUploadSizeExceededException ex) {
        return json(HttpStatus.PAYLOAD_TOO_LARGE, "File is too large. Maximum upload size is 10MB.");
    }

    /** Unknown static path (e.g. a missing /uploads file): a plain 404, not an error-level log. */
    @ExceptionHandler(org.springframework.web.servlet.resource.NoResourceFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNoResource(
            org.springframework.web.servlet.resource.NoResourceFoundException ex) {
        return json(HttpStatus.NOT_FOUND, "Not found");
    }

    /**
     * Spring MVC's own request errors all implement {@link org.springframework.web.ErrorResponse} and already carry the
     * right status and response headers: an unsupported method (405, with {@code Allow}), an unsupported media type
     * (415, with {@code Accept}), nothing acceptable (406), a missing header/cookie/parameter/part, a binding failure.
     * Without this they fell into the generic 500 below and were logged as if the server had broken.
     */
    private static ResponseEntity<ApiResponse<Void>> frameworkError(org.springframework.web.ErrorResponse error, Exception ex) {
        if (error.getStatusCode().value() == HttpStatus.NOT_ACCEPTABLE.value()) {
            // Nothing the caller accepts can be written - a JSON error body included - so send the status alone.
            return ResponseEntity.status(error.getStatusCode()).build();
        }
        String detail = error.getBody() != null ? error.getBody().getDetail() : null;
        if (detail == null) {
            detail = ex.getMessage();
        }
        return ResponseEntity.status(error.getStatusCode())
            .headers(error.getHeaders())
            .contentType(MediaType.APPLICATION_JSON)
            .body(ApiResponse.error(detail != null ? detail : "The request could not be processed."));
    }

    /**
     * Tomcat could not decode the request's parameters, so the caller's bytes never became a name/value pair:
     * a percent-escape that is not valid UTF-8 (a lone UTF-16 surrogate such as {@code %ED%A0%80}, a truncated
     * escape, an invalid byte), a {@code &=value} chunk with no name, more parameters than
     * {@code server.tomcat.max-parameter-count}, or a form body over {@code max-http-form-post-size}.
     *
     * <p>All of that is caller input, but {@code InvalidParameterException} is an {@code IllegalStateException} and
     * not a Spring {@link org.springframework.web.ErrorResponse}, so it fell into the generic 500 below and was
     * logged at ERROR with a stack trace - a log full of noise that any client could generate at will. Tomcat
     * already decided the status it wants ({@link org.apache.tomcat.util.http.InvalidParameterException#getErrorCode()}:
     * 400, or 413 for an over-sized body), which is what {@code StandardWrapperValve} would have used had the
     * exception not been resolved here first; anything not a 4xx is treated as a 400 rather than trusted as a 5xx.
     *
     * <p>Handled here rather than by a Tomcat/servlet setting on purpose: the container has no option that turns
     * undecodable parameters into a clean 400 for Spring MVC (the alternatives either silently drop the caller's
     * input or bypass this app's error body), and only an {@code @ExceptionHandler} can answer in the
     * {@link ApiResponse} shape the frontend parses. The exception message quotes the offending parameter name and
     * value, so it goes to the log at debug level and never into the response.
     */
    @ExceptionHandler(org.apache.tomcat.util.http.InvalidParameterException.class)
    public ResponseEntity<ApiResponse<Void>> handleUndecodableParameters(
            org.apache.tomcat.util.http.InvalidParameterException ex) {
        log.debug("Undecodable request parameters: {}", ex.getMessage());

        HttpStatus status = HttpStatus.resolve(ex.getErrorCode());
        if (status == null || !status.is4xxClientError()) {
            status = HttpStatus.BAD_REQUEST;
        }
        return json(status, status == HttpStatus.PAYLOAD_TOO_LARGE
            ? "The request is too large."
            : "The request could not be read. Please check the URL and its parameters.");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleGeneral(Exception ex) {
        // The caller's fault, not ours: keep the framework's status and stay out of the error log.
        if (ex instanceof org.springframework.web.ErrorResponse error && !error.getStatusCode().is5xxServerError()) {
            log.debug("Rejected request ({}): {}", error.getStatusCode().value(), ex.getMessage());
            return frameworkError(error, ex);
        }
        log.error("Unhandled exception", ex);
        return json(HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred. Please try again later.");
    }
}
