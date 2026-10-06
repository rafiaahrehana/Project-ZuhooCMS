package com.zuhoocms.modules.hrm.announcement;

import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.AnnouncementDraftPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.department.Department;
import com.zuhoocms.enums.AnnouncementAudience;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.hrm.department.DepartmentRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor

public class AnnouncementServiceImpl implements AnnouncementService {

    private final AnnouncementRepository announcementRepository;
    private final EmployeeRepository employeeRepository;
    private final DepartmentRepository departmentRepository;
    private final NotificationService notificationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final CompanyRepository companyRepository;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final ObjectMapper objectMapper;
    private final EmailService emailService;
    private final EmailBranding emailBranding;

    @Override
    @Transactional
    public AnnouncementResponse create(AnnouncementRequest request) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_CREATE);
        Long companyId = requireCompanyId();

        rejectUnsupportedAudience(request.getAudience());
        requireDepartmentForDepartmentAudience(request.getAudience(), request.getTargetDepartmentId());
        Department targetDept = null;
        if (request.getAudience() == AnnouncementAudience.DEPARTMENT && request.getTargetDepartmentId() != null) {
            targetDept = departmentRepository.findByIdAndCompanyId(request.getTargetDepartmentId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "Department not found: " + request.getTargetDepartmentId()));
        }

        Announcement announcement = Announcement.builder()
            .title(request.getTitle())
            .body(request.getBody())
            .audience(request.getAudience() != null ? request.getAudience() : AnnouncementAudience.ALL)
            .targetDepartment(targetDept)
            .expiresAt(request.getExpiresAt())
            .scheduledAt(request.getScheduledAt())
            .notifyAll(request.isNotifyAll())
            .priority(request.getPriority() != null ? request.getPriority() : 0)
            .attachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl()))
            .published(false)
            .company(companyRef(companyId))
            .createdBy(securityUtil.getCurrentUser())
            .build();

        announcementRepository.save(announcement);
        return AnnouncementMapper.toAnnouncementResponse(announcement);
    }

    @Override
    @Transactional(readOnly = true)
    public AnnouncementResponse getById(Long id) {
        Announcement announcement = findInTenant(id);
        // Without ANNOUNCEMENT_VIEW a viewer gets exactly their /active feed: drafts and other audiences' notices were id-guessable.
        if (!authorizationService.hasPermission(PermissionCode.ANNOUNCEMENT_VIEW)
                && !visibleInFeed(announcement, requireCompanyId())) {
            throw new ResourceNotFoundException("Announcement not found: " + id);
        }
        return AnnouncementMapper.toAnnouncementResponse(announcement);
    }

    private boolean visibleInFeed(Announcement a, Long companyId) {
        if (!a.isPublished()) return false;
        if (a.getExpiresAt() != null && !a.getExpiresAt().isAfter(LocalDateTime.now())) return false;
        com.zuhoocms.auth.user.User currentUser = securityUtil.getCurrentUser();
        com.zuhoocms.modules.hrm.employee.Employee me = currentUser != null
                ? employeeRepository.findByUserId(currentUser.getId()).orElse(null) : null;
        if (me == null) return true; // same rule as listActive(): no employee profile sees everything
        boolean iAmManager = employeeRepository.existsByCompanyIdAndReportingManagerIdAndActiveTrue(companyId, me.getId());
        return appliesToViewer(a, me, iAmManager);
    }

    /** A DEPARTMENT announcement with no department used to fall back to notifying the whole company. */
    private void requireDepartmentForDepartmentAudience(AnnouncementAudience audience, Long targetDepartmentId) {
        if (audience == AnnouncementAudience.DEPARTMENT && targetDepartmentId == null) {
            throw new BadRequestException("Choose a target department for a department announcement");
        }
    }



    @Override
    @Transactional(readOnly = true)
    public Page<AnnouncementResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_VIEW);
        return announcementRepository.findByCompanyId(requireCompanyId(), pageable)
            .map(AnnouncementMapper::toAnnouncementResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AnnouncementResponse> listActive() {
        // Read-only notice board: any logged-in employee sees their company's active announcements regardless of ANNOUNCEMENT_VIEW.
        // Filtered by audience, so a DEPARTMENT-targeted announcement is no longer readable company-wide.
        Long companyId = requireCompanyId();
        List<Announcement> active = announcementRepository.findActiveByCompanyId(companyId, LocalDateTime.now());

        com.zuhoocms.auth.user.User currentUser = securityUtil.getCurrentUser();
        com.zuhoocms.modules.hrm.employee.Employee me = currentUser != null
                ? employeeRepository.findByUserId(currentUser.getId()).orElse(null) : null;
        // No employee profile (e.g. the company owner) sees everything: no department or manager status to scope by.
        if (me == null) {
            return active.stream().map(AnnouncementMapper::toAnnouncementResponse).toList();
        }
        boolean iAmManager = employeeRepository.existsByCompanyIdAndReportingManagerIdAndActiveTrue(companyId, me.getId());

        return active.stream()
            .filter(a -> appliesToViewer(a, me, iAmManager))
            .map(AnnouncementMapper::toAnnouncementResponse).toList();
    }

    private boolean appliesToViewer(Announcement a, com.zuhoocms.modules.hrm.employee.Employee me, boolean iAmManager) {
        return switch (a.getAudience()) {
            case MANAGERS -> iAmManager;
            case EMPLOYEES -> !iAmManager;
            case DEPARTMENT -> a.getTargetDepartment() != null && me.getDepartment() != null
                    && me.getDepartment().getId().equals(a.getTargetDepartment().getId());
            case ALL, SPECIFIC -> true; // SPECIFIC has no recipient-list model yet - see rejectUnsupportedAudience
        };
    }

    /** SPECIFIC has no targetEmployeeIds model on the entity yet - reject rather than silently notifying/showing everyone. */
    private void rejectUnsupportedAudience(AnnouncementAudience audience) {
        if (audience == AnnouncementAudience.SPECIFIC) {
            throw new BadRequestException(
                    "Targeting specific recipients isn't available yet - choose All, Employees, Managers, or Department");
        }
    }

    @Override
    @Transactional
    public AnnouncementResponse publish(Long id) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_UPDATE);
        Long companyId = requireCompanyId();
        Announcement announcement = findInTenant(id);
        if (announcement.isPublished() || !doPublish(announcement, companyId)) {
            throw new BadRequestException("Announcement is already published");
        }
        return AnnouncementMapper.toAnnouncementResponse(announcement);
    }

    /**
     * System entry point for AnnouncementScheduledPublishScheduler: no security context, so company id comes from the entity and the permission check is skipped.
     * Not transactional itself - each announcement publishes in its own transaction, so one failure doesn't roll back the whole sweep.
     */
    @Override
    public void publishDueScheduled() {
        List<Long> dueIds = aiTx.load(() -> announcementRepository
                .findByPublishedFalseAndDeletedFalseAndScheduledAtLessThanEqual(LocalDateTime.now())
                .stream().map(Announcement::getId).toList());
        for (Long id : dueIds) {
            try {
                aiTx.persist(() -> {
                    announcementRepository.findById(id)
                            .filter(a -> !a.isPublished())
                            .ifPresent(a -> doPublish(a, a.getCompany().getId()));
                    return null;
                });
            } catch (Exception ex) {
                log.error("Scheduled publish failed for announcement {}", id, ex);
            }
        }
    }

    /** Returns false if another caller published it first: the conditional UPDATE is the single point deciding who fans out notifications. */
    private boolean doPublish(Announcement announcement, Long companyId) {
        LocalDateTime now = LocalDateTime.now();
        if (announcementRepository.markPublishedIfUnpublished(announcement.getId(), now) == 0) {
            return false;
        }
        announcement.setPublished(true);
        announcement.setPublishedAt(now);

        if (announcement.isNotifyAll()) {
            // Emails as well as in-app entries: the "Send Email Notification to All" checkbox previously only created in-app notifications.
            EmailBranding.Data branding = null;
            try {
                Company fullCompany = companyRepository.findById(companyId).orElse(null);
                if (fullCompany != null) branding = emailBranding.from(fullCompany);
            } catch (Exception ex) {
                log.warn("Could not load branding for announcement email (company {}): {}", companyId, ex.getMessage());
            }

            int pageNum = 0;
            final int PAGE_SIZE = 100;
            org.springframework.data.domain.Page<com.zuhoocms.modules.hrm.employee.Employee> page;
            do {
                // Each branch queries only its real audience; EMPLOYEES/MANAGERS/targetless DEPARTMENT used to fall through to everyone.
                // Sorted by id: unordered offset paging can skip or repeat people between pages.
                // Same population as the /active feed (appliesToViewer); a DEPARTMENT row with no department reaches nobody.
                PageRequest pageRequest = PageRequest.of(pageNum, PAGE_SIZE, Sort.by("id"));
                page = switch (announcement.getAudience()) {
                    case DEPARTMENT -> announcement.getTargetDepartment() != null
                            ? announcementRepository.findActiveEmployeesInDepartment(
                                companyId, announcement.getTargetDepartment().getId(), pageRequest)
                            : Page.empty(pageRequest);
                    case MANAGERS -> employeeRepository.findManagersByCompanyId(companyId, pageRequest);
                    case EMPLOYEES -> employeeRepository.findNonManagersByCompanyId(companyId, pageRequest);
                    default -> announcementRepository.findActiveEmployees(companyId, pageRequest);
                };
                EmailBranding.Data brandingForLoop = branding;
                page.getContent().forEach(emp -> {
                    if (emp.getUser() != null) {
                        notificationService.send(CreateNotificationRequest.of(
                            NotificationType.ANNOUNCEMENT,
                            announcement.getTitle(),
                            announcement.getBody().length() > 150
                                ? announcement.getBody().substring(0, 147) + "..."
                                : announcement.getBody(),
                            "/announcements/" + announcement.getId(),
                            emp.getUser().getId(),
                            companyId
                        ));
                        if (brandingForLoop != null && emp.getUser().getEmail() != null) {
                            try {
                                emailService.sendAnnouncementEmail(
                                    emp.getUser().getEmail(), emp.getUser().getFirstName(),
                                    announcement.getTitle(), announcement.getBody(), brandingForLoop);
                            } catch (Exception ex) {
                                log.warn("Announcement email failed for {}: {}", emp.getUser().getEmail(), ex.getMessage());
                            }
                        }
                    }
                });
                pageNum++;
            } while (page.hasNext());
        }
        return true;
    }

    @Override
    @Transactional
    public AnnouncementResponse update(Long id, AnnouncementRequest request) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_UPDATE);
        Long companyId = requireCompanyId();
        Announcement announcement = findInTenant(id);
        if (announcement.isPublished()) throw new BadRequestException("Cannot edit a published announcement");
        if (request.getTitle()!= null) announcement.setTitle(request.getTitle());
        if (request.getBody()!= null) announcement.setBody(request.getBody());
        if (request.getAudience()!= null) {
            rejectUnsupportedAudience(request.getAudience());
            announcement.setAudience(request.getAudience());
        }
        if (request.getAttachmentUrl()!= null) announcement.setAttachmentUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getAttachmentUrl(), announcement.getAttachmentUrl()));
        if (request.getPriority()!= null) announcement.setPriority(request.getPriority());
        announcement.setExpiresAt(request.getExpiresAt());
        announcement.setScheduledAt(request.getScheduledAt());
        announcement.setNotifyAll(request.isNotifyAll());
        if (announcement.getAudience() == AnnouncementAudience.DEPARTMENT) {
            if (request.getTargetDepartmentId() != null) {
                announcement.setTargetDepartment(
                    departmentRepository.findByIdAndCompanyId(request.getTargetDepartmentId(), companyId)
                        .orElseThrow(() -> new ResourceNotFoundException("Department not found")));
            }
            requireDepartmentForDepartmentAudience(announcement.getAudience(),
                announcement.getTargetDepartment() != null ? announcement.getTargetDepartment().getId() : null);
        } else {
            // Clear a stale department so a non-department announcement doesn't look department-scoped.
            announcement.setTargetDepartment(null);
        }
        return AnnouncementMapper.toAnnouncementResponse(announcement);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_DELETE);
        Announcement a = findInTenant(id);
        if (a.isPublished()) throw new BadRequestException("Cannot delete a published announcement");
        a.softDelete();
    }

    // No @Transactional on purpose: aiTx.load() commits before the provider call so no DB connection is held across it - see AiTransactionBoundary.
    @Override
    public AnnouncementDraftResponse draftWithAi(AnnouncementDraftRequest request) {
        authorizationService.checkPermission(PermissionCode.ANNOUNCEMENT_CREATE);
        Long companyId = requireCompanyId();

        String prompt = aiTx.load(() -> {
            Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found: " + companyId));

            return AnnouncementDraftPromptBuilder.builder()
                .setCompanyName(company.getCompanyName())
                .setToday(LocalDate.now())
                .setInstructions(request.getInstructions())
                .build();
        });

        String raw = aiService.generateRaw(AiFeature.ANNOUNCEMENT_DRAFT, prompt);
        return parseDraft(raw, request.getInstructions());
    }

    private AnnouncementDraftResponse parseDraft(String raw, String fallbackInstructions) {
        AnnouncementDraftResponse response = new AnnouncementDraftResponse();
        try {
            String cleaned = raw.trim();
            if (cleaned.startsWith("```")) {
                cleaned = cleaned.replaceFirst("^```[a-zA-Z]*\\n?", "").replaceFirst("```\\s*$", "");
            }
            JsonNode node = objectMapper.readTree(cleaned);
            response.setTitle(node.path("title").asText(null));
            response.setBody(node.path("body").asText(null));
        } catch (Exception ignored) {
            // Model didn't return valid JSON: fall back to the raw text as the body rather than failing the request.
        }
        if (response.getTitle() == null || response.getTitle().isBlank()) {
            response.setTitle(fallbackInstructions.length() > 80
                ? fallbackInstructions.substring(0, 77) + "..." : fallbackInstructions);
        }
        if (response.getBody() == null || response.getBody().isBlank()) {
            response.setBody(raw);
        }
        return response;
    }

    private Announcement findInTenant(Long id) {
        return announcementRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Announcement not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company(); c.setId(companyId); return c;
    }
}

