package com.zuhoocms.modules.crm.opportunity;

import com.zuhoocms.core.automation.AutomationEventPublisher;
import com.zuhoocms.enums.LeadSource;
import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.crm.activity.CrmActivityType;
import com.zuhoocms.modules.crm.activity.CrmActivityService;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.contact.ClientContact;
import com.zuhoocms.modules.crm.contact.ClientContactRepository;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.crm.duplicate.DuplicateDetectionService;
import com.zuhoocms.modules.crm.duplicate.DuplicateMatch;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.enums.ClientStatus;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Transactional
public class OpportunityServiceImpl implements OpportunityService {

    private final OpportunityRepository opportunityRepository;
    private final ClientRepository clientRepository;
    private final ClientContactRepository clientContactRepository;
    private final LeadRepository leadRepository;
    private final EmployeeRepository employeeRepository;
    private final CrmActivityService crmActivityService;
    private final AutomationEventPublisher automationEventPublisher;
    private final NotificationService notificationService;
    private final SecurityUtil securityUtil;
    private final DuplicateDetectionService duplicateDetectionService;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.crm.tag.TagRepository tagRepository;
    private final jakarta.persistence.EntityManager entityManager;

    /** Advisory lock namespace for win-time client resolution; company id is the other half, so tenants never block each other. */
    private static final int WON_CLIENT_LOCK_NAMESPACE = 0x43524D1;

    /**
     * Which stage moves are legal; changeStage previously accepted anything, making conversion and cycle-time figures meaningless.
     *
     *  - between open stages, anything goes (the board is drag-and-drop),
     *  - LOST is reachable from every stage, including WON,
     *  - WON is only reachable from NEGOTIATION, or back from LOST via re-opening,
     *  - re-opening restarts the deal: LOST goes back to QUALIFICATION, WON back to NEGOTIATION.
     */
    private static final Map<OpportunityStage, EnumSet<OpportunityStage>> ALLOWED_TRANSITIONS =
            buildAllowedTransitions();

    private static Map<OpportunityStage, EnumSet<OpportunityStage>> buildAllowedTransitions() {
        EnumSet<OpportunityStage> open = EnumSet.of(OpportunityStage.QUALIFICATION,
                OpportunityStage.PRESENTATION, OpportunityStage.PROPOSAL, OpportunityStage.NEGOTIATION);

        Map<OpportunityStage, EnumSet<OpportunityStage>> allowed = new EnumMap<>(OpportunityStage.class);
        for (OpportunityStage stage : open) {
            EnumSet<OpportunityStage> targets = EnumSet.copyOf(open);
            targets.add(OpportunityStage.LOST);
            allowed.put(stage, targets);
        }
        allowed.get(OpportunityStage.NEGOTIATION).add(OpportunityStage.WON);
        allowed.put(OpportunityStage.WON, EnumSet.of(OpportunityStage.NEGOTIATION, OpportunityStage.LOST));
        allowed.put(OpportunityStage.LOST, EnumSet.of(OpportunityStage.QUALIFICATION));
        return allowed;
    }

    @Override
    public OpportunityResponse create(OpportunityRequest request) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_CREATE);
        Long companyId = requireCompanyId();
        if (request.getClientId() == null) {
            throw new BadRequestException("Client is required when creating a deal directly");
        }
        Client client = clientRepository.findByIdAndCompanyId(request.getClientId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Client not found"));

        Opportunity opportunity = buildFromRequest(request, client, client.getCompany(), companyId);
        opportunity = opportunityRepository.save(opportunity);

        crmActivityService.logSystemActivity(CrmActivityType.NOTE,
                "Opportunity created",
                "Opportunity \"" + opportunity.getName() + "\" created in stage " + opportunity.getStage(),
                client.getId(), opportunity.getId());

        return OpportunityMapper.toResponse(opportunity);
    }

    // An Opportunity may have no Client yet: it is created/linked when the deal reaches Won (see changeStage), unless the Lead already has one or a clientId is passed.
    @Override
    public OpportunityResponse createFromLead(Long leadId, OpportunityRequest request) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_CREATE);
        Long companyId = requireCompanyId();
        // PESSIMISTIC_WRITE: isConverted() is check-then-act, so concurrent converts would spawn duplicate opportunities.
        Lead lead = leadRepository.findByIdAndCompanyIdForUpdate(leadId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Lead not found"));

        // Enforced here, not only in LeadServiceImpl.convertToOpportunity: POST /api/crm/opportunities/from-lead/{leadId} reaches this directly with only OPPORTUNITY_CREATE.
        if (lead.isConverted()) {
            throw new BadRequestException("Lead is already converted");
        }
        if (lead.getStatus() != LeadStatus.QUALIFIED) {
            throw new BadRequestException("Only a Qualified lead can be converted to an opportunity");
        }

        Client client = null;
        if (lead.getConvertedClient() != null) {
            client = lead.getConvertedClient();
        } else if (request.getClientId() != null) {
            client = clientRepository.findByIdAndCompanyId(request.getClientId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Client not found"));
        }
        if (client != null) {
            request.setClientId(client.getId());
        }

        // Description, notes and tags used to be dropped on conversion, losing the qualifying context the pipeline is filtered by.
        carryLeadContextToRequest(request, lead);

        Opportunity opportunity = buildFromRequest(request, client, lead.getCompany(), companyId);
        opportunity.setSourceLead(lead);
        if (request.getSource() == null && lead.getSource() != null) {
            opportunity.setSource(lead.getSource());
        }
        if (request.getAmount() == null && lead.getEstimatedValue() != null) {
            opportunity.setAmount(lead.getEstimatedValue());
        }
        if (request.getExpectedCloseDate() == null && lead.getExpectedCloseDate() != null) {
            opportunity.setExpectedCloseDate(lead.getExpectedCloseDate());
        }
        opportunity = opportunityRepository.save(opportunity);

        lead.setConverted(true);
        lead.setConvertedAt(LocalDateTime.now());
        leadRepository.save(lead);

        crmActivityService.logSystemActivity(CrmActivityType.NOTE,
                "Opportunity created from lead",
                "Opportunity \"" + opportunity.getName() + "\" created from lead \"" + lead.getContactName() + "\"",
                client != null ? client.getId() : null, opportunity.getId());

        return OpportunityMapper.toResponse(opportunity);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<OpportunityResponse> listAll(OpportunityStage stage, Boolean openOnly, Long clientId, Long ownerId,
            Long tagId, String keyword, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_VIEW);
        Long companyId = requireCompanyId();
        Page<Opportunity> page;
        if (keyword != null && !keyword.isBlank()) {
            page = opportunityRepository.searchOpportunities(companyId, escapeLikeKeyword(keyword.trim()), pageable);
        } else if (stage != null) {
            page = opportunityRepository.findByCompanyIdAndStage(companyId, stage, pageable);
        } else if (clientId != null) {
            page = opportunityRepository.findByCompanyIdAndClientId(companyId, clientId, pageable);
        } else if (ownerId != null) {
            page = opportunityRepository.findByCompanyIdAndOwnerId(companyId, ownerId, pageable);
        } else if (tagId != null) {
            page = opportunityRepository.findByCompanyIdAndTagsId(companyId, tagId, pageable);
        } else if (Boolean.TRUE.equals(openOnly)) {
            // Without this the list returns closed deals too, burying open ones behind pages of history.
            page = opportunityRepository.findByCompanyIdAndStageNotIn(
                    companyId, List.of(OpportunityStage.WON, OpportunityStage.LOST), pageable);
        } else {
            page = opportunityRepository.findByCompanyId(companyId, pageable);
        }
        return page.map(OpportunityMapper::toResponse);
    }

    /** Copies lead context onto the request without overwriting caller-supplied values; description and notes are merged since reps use both boxes. */
    private void carryLeadContextToRequest(OpportunityRequest request, Lead lead) {
        if (request.getDescription() == null || request.getDescription().isBlank()) {
            String description = joinNonBlank(lead.getDescription(), lead.getNotes());
            if (description != null) {
                request.setDescription(description);
            }
        }
        if (request.getTagIds() == null && lead.getTags() != null && !lead.getTags().isEmpty()) {
            request.setTagIds(lead.getTags().stream()
                    .map(com.zuhoocms.modules.crm.tag.Tag::getId)
                    .toList());
        }
    }

    private String joinNonBlank(String first, String second) {
        boolean hasFirst = first != null && !first.isBlank();
        boolean hasSecond = second != null && !second.isBlank();
        if (hasFirst && hasSecond) return first.trim() + "\n\n" + second.trim();
        if (hasFirst) return first.trim();
        if (hasSecond) return second.trim();
        return null;
    }

    @Override
    @Transactional(readOnly = true)
    public OpportunityResponse getById(Long id) {
        // Was unguarded: without OPPORTUNITY_VIEW a user could still read any single deal by walking ids.
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_VIEW);
        return OpportunityMapper.toResponse(findOwned(id));
    }

    @Override
    public OpportunityResponse update(Long id, OpportunityRequest request) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_UPDATE);
        Long companyId = requireCompanyId();
        Opportunity opportunity = findOwned(id);

        if (opportunity.getStage().isClosed()) {
            throw new BadRequestException(
                    "Closed opportunities cannot be edited. Reopen it by changing the stage first");
        }

        if (request.getName() != null)
            opportunity.setName(request.getName());
        // Null-skipped: assigned unconditionally, an amount-only PATCH from the pipeline card wiped description and nextStep.
        if (request.getDescription() != null)
            opportunity.setDescription(request.getDescription());
        if (request.getNextStep() != null)
            opportunity.setNextStep(request.getNextStep());
        if (request.getAmount() != null)
            opportunity.setAmount(request.getAmount());
        if (request.getProbability() != null)
            opportunity.setProbability(request.getProbability());
        if (request.getExpectedCloseDate() != null)
            opportunity.setExpectedCloseDate(request.getExpectedCloseDate());
        if (request.getSource() != null)
            opportunity.setSource(request.getSource());

        if (request.getContactId() != null) {
            ClientContact contact = clientContactRepository.findByIdAndCompanyId(request.getContactId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Contact not found"));
            if (opportunity.getClient() != null
                    && !contact.getClient().getId().equals(opportunity.getClient().getId())) {
                throw new BadRequestException("Contact does not belong to the opportunity's client");
            }
            opportunity.setContact(contact);
        }
        if (request.getOwnerId() != null) {
            opportunity.setOwner(findEmployee(request.getOwnerId(), companyId));
        }
        if (request.getTagIds() != null) {
            opportunity.setTags(resolveTags(request.getTagIds(), companyId));
        }

        return OpportunityMapper.toResponse(opportunityRepository.save(opportunity));
    }

    @Override
    public OpportunityResponse changeStage(Long id, ChangeStageRequest request) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_UPDATE);
        Opportunity opportunity = findOwned(id);
        OpportunityStage from = opportunity.getStage();
        OpportunityStage to = request.getStage();

        if (from == to) {
            return OpportunityMapper.toResponse(opportunity);
        }
        if (!ALLOWED_TRANSITIONS.getOrDefault(from, EnumSet.noneOf(OpportunityStage.class)).contains(to)) {
            throw new BadRequestException("A deal cannot move from " + from + " to " + to
                    + ". Allowed from " + from + ": "
                    + ALLOWED_TRANSITIONS.getOrDefault(from, EnumSet.noneOf(OpportunityStage.class)));
        }
        if (to == OpportunityStage.LOST) {
            // The picklist code is what win/loss analysis aggregates; free text is mandatory only for OTHER.
            if (request.getLostReasonCode() == null) {
                throw new BadRequestException("A lost reason is required when closing an opportunity as lost");
            }
            if (request.getLostReasonCode() == com.zuhoocms.enums.LostReason.OTHER
                    && (request.getLostReason() == null || request.getLostReason().isBlank())) {
                throw new BadRequestException("Please describe the reason when choosing Other");
            }
        }

        opportunity.setStage(to);
        // Stage default only when the caller stated no probability: overwriting a rep's explicit figure made the weighted forecast a function of the board layout.
        opportunity.setProbability(request.getProbability() != null
                ? request.getProbability()
                : to.getDefaultProbability());
        opportunity.setStageChangedAt(LocalDateTime.now());

        // Leaving WON in ANY direction returns the money: WON -> LOST used to skip this, leaving the credit on the client's lifetime value forever.
        if (from == OpportunityStage.WON && opportunity.getClient() != null) {
            debitClientLifetimeValue(opportunity);
        }

        DuplicateMatch autoLinkedDuplicate = null;
        if (to.isClosed()) {
            opportunity.setActualCloseDate(LocalDate.now());
            if (to == OpportunityStage.LOST) {
                opportunity.setLostReason(request.getLostReason());
                opportunity.setLostReasonCode(request.getLostReasonCode());
                notifyOwnerOpportunityLost(opportunity);
            } else {
                opportunity.setLostReason(null);
                opportunity.setLostReasonCode(null);
                if (opportunity.getClient() == null) {
                    autoLinkedDuplicate = resolveClientForWonOpportunity(opportunity, request);
                }
                creditClientLifetimeValue(opportunity);
                automationEventPublisher.publishOpportunityWon(
                        this, opportunity.getCompany().getId(),
                        opportunity.getId(), opportunity.getClient().getId(),
                        opportunity.getName());
                notifyOwnerOpportunityWon(opportunity);
            }
        } else {
            opportunity.setActualCloseDate(null);
            opportunity.setLostReason(null);
            opportunity.setLostReasonCode(null);
        }

        opportunity = opportunityRepository.save(opportunity);

        crmActivityService.logSystemActivity(CrmActivityType.STAGE_CHANGE,
                "Stage changed",
                "Stage moved from " + from + " to " + to,
                opportunity.getClient() != null ? opportunity.getClient().getId() : null,
                opportunity.getId());

        OpportunityResponse response = OpportunityMapper.toResponse(opportunity);
        response.setPossibleDuplicate(autoLinkedDuplicate);
        return response;
    }

    @Override
    @Transactional(readOnly = true)
    public PipelineSummaryResponse getPipelineSummary() {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_VIEW);
        Long companyId = requireCompanyId();
        List<OpportunityRepository.PipelineStageSummary> rows = opportunityRepository.summarizePipeline(companyId);

        PipelineSummaryResponse response = new PipelineSummaryResponse();
        BigDecimal open = BigDecimal.ZERO;
        BigDecimal weighted = BigDecimal.ZERO;
        BigDecimal won = BigDecimal.ZERO;
        long openDeals = 0;

        EnumSet<OpportunityStage> closed = EnumSet.of(OpportunityStage.WON, OpportunityStage.LOST);

        response.setStages(rows.stream().map(row -> {
            PipelineSummaryResponse.StageSummary s = new PipelineSummaryResponse.StageSummary();
            s.setStage(row.getStage());
            s.setDealCount(row.getDealCount());
            s.setTotalAmount(money(row.getTotalAmount()));
            s.setWeightedAmount(money(row.getWeightedAmount()));
            return s;
        }).toList());

        for (OpportunityRepository.PipelineStageSummary row : rows) {
            if (row.getStage() == OpportunityStage.WON) {
                won = won.add(row.getTotalAmount());
            } else if (!closed.contains(row.getStage())) {
                open = open.add(row.getTotalAmount());
                weighted = weighted.add(row.getWeightedAmount());
                openDeals += row.getDealCount();
            }
        }
        response.setOpenPipelineValue(money(open));
        response.setWeightedForecast(money(weighted));
        response.setWonValue(money(won));
        response.setTotalOpenDeals(openDeals);
        return response;
    }

    /** Rounds to 2dp: the weighted-forecast division carries more scale than currency, e.g. 1234.5600000000002. */
    private BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }

    @Override
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_DELETE);
        Opportunity opportunity = findOwned(id);
        opportunity.softDelete();
        opportunityRepository.save(opportunity);
    }

    // `client` may be null (created straight from a Lead), so `company` is passed separately.
    private Opportunity buildFromRequest(OpportunityRequest request, Client client, Company company, Long companyId) {
        OpportunityStage stage = request.getStage() != null ? request.getStage() : OpportunityStage.QUALIFICATION;

        Opportunity opportunity = Opportunity.builder()
                .name(request.getName())
                .description(request.getDescription())
                .stage(stage)
                .source(request.getSource() != null ? request.getSource() : LeadSource.OTHER)
                .amount(request.getAmount())
                .probability(
                        request.getProbability() != null ? request.getProbability() : stage.getDefaultProbability())
                .expectedCloseDate(request.getExpectedCloseDate())
                .nextStep(request.getNextStep())
                .client(client)
                .company(company)
                .build();

        if (request.getContactId() != null && client != null) {
            ClientContact contact = clientContactRepository.findByIdAndCompanyId(request.getContactId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Contact not found"));
            if (!contact.getClient().getId().equals(client.getId())) {
                throw new BadRequestException("Contact does not belong to the selected client");
            }
            opportunity.setContact(contact);
        }
        if (request.getOwnerId() != null) {
            opportunity.setOwner(findEmployee(request.getOwnerId(), companyId));
        }
        if (request.getTagIds() != null && !request.getTagIds().isEmpty()) {
            opportunity.setTags(resolveTags(request.getTagIds(), companyId));
        }
        return opportunity;
    }

    /** Tag ids -> Tag rows, rejecting any that don't resolve. See TagResolver. */
    private List<com.zuhoocms.modules.crm.tag.Tag> resolveTags(List<Long> tagIds, Long companyId) {
        return com.zuhoocms.modules.crm.support.TagResolver.resolve(tagRepository, tagIds, companyId);
    }

    /** Adds a won deal's amount to the client's lifetime value in the database (see ClientRepository.adjustLifetimeValue): Client has no @Version, so read-modify-write lost one of two simultaneous wins. */
    private void creditClientLifetimeValue(Opportunity opportunity) {
        if (opportunity.getAmount() == null)
            return;
        adjustLifetimeValue(opportunity.getClient(), opportunity.getAmount());
    }

    private void notifyOwnerOpportunityLost(Opportunity opportunity) {
        Employee owner = opportunity.getOwner();
        if (owner == null || owner.getUser() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.OPPORTUNITY_LOST,
                "Opportunity Lost",
                "Opportunity \"" + opportunity.getName() + "\" was marked as lost.",
                "/crm/pipeline",
                owner.getUser().getId(),
                opportunity.getCompany().getId()
        ));
    }

    private void notifyOwnerOpportunityWon(Opportunity opportunity) {
        Employee owner = opportunity.getOwner();
        if (owner == null || owner.getUser() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.OPPORTUNITY_WON,
                "Opportunity Won",
                "Opportunity \"" + opportunity.getName() + "\" was won.",
                "/crm/pipeline",
                owner.getUser().getId(),
                opportunity.getCompany().getId()
        ));
    }

    // Resolves the Client for a Won Opportunity that has none: explicit link/force choices win, else duplicate detection links a match or a new Client is created without a portal login (see CreateClientRequest.provisionPortalLogin).
    private DuplicateMatch resolveClientForWonOpportunity(Opportunity opportunity, ChangeStageRequest request) {
        Long companyId = opportunity.getCompany().getId();

        // Serialises win-time client resolution per company: everything below is check-then-create, so two simultaneous wins for the same new account created it twice.
        // A transaction-scoped Postgres advisory lock is per-database, so it holds across application instances and releases at commit or rollback.
        entityManager.createNativeQuery("SELECT pg_advisory_xact_lock(:namespace, :companyId)")
                .setParameter("namespace", WON_CLIENT_LOCK_NAMESPACE)
                .setParameter("companyId", companyId.intValue())
                .getSingleResult();

        // Linked on all three paths below, so a converted Lead can be traced to the Client it became.
        Lead sourceLead = opportunity.getSourceLead();

        if (request.getLinkToExistingClientId() != null) {
            Client existing = clientRepository.findByIdAndCompanyId(request.getLinkToExistingClientId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Client not found"));
            opportunity.setClient(existing);
            linkLeadToConvertedClient(sourceLead, existing);
            return null;
        }

        if (!request.isForceCreateNewClient()) {
            Optional<DuplicateMatch> duplicate = findDuplicateForOpportunity(opportunity);
            if (duplicate.isPresent()) {
                Client existing = clientRepository.findByIdAndCompanyId(duplicate.get().getClientId(), companyId)
                        .orElseThrow(() -> new ResourceNotFoundException("Client not found"));
                opportunity.setClient(existing);
                linkLeadToConvertedClient(sourceLead, existing);
                return duplicate.get();
            }
        }

        String companyName = sourceLead != null ? sourceLead.getCompanyName() : null;
        String fallbackName = companyName != null ? companyName
                : sourceLead != null ? sourceLead.getContactName()
                : opportunity.getName();
        Client client = Client.builder()
                .clientCompanyName(fallbackName)
                .company(companyRef(companyId))
                .status(ClientStatus.ACTIVE)
                .industry(sourceLead != null ? sourceLead.getIndustry() : null)
                .onboardedAt(LocalDate.now())
                .build();
        clientRepository.save(client);
        opportunity.setClient(client);
        linkLeadToConvertedClient(sourceLead, client);

        // findPossibleDuplicateClient() matches email and phone against ClientContact rows, so a client with no contact can only ever be matched by company name.
        createPrimaryContactFromLead(client, sourceLead, companyId);
        return null;
    }

    private void linkLeadToConvertedClient(Lead sourceLead, Client client) {
        if (sourceLead == null) return;
        sourceLead.setConvertedClient(client);
        leadRepository.save(sourceLead);
    }

    /** Creates the client's first contact from the lead; no-op without an email or phone, since a name-only contact adds nothing duplicate detection can use. */
    private void createPrimaryContactFromLead(Client client, Lead lead, Long companyId) {
        if (lead == null) return;

        boolean hasEmail = lead.getEmail() != null && !lead.getEmail().isBlank();
        boolean hasPhone = lead.getPhone() != null && !lead.getPhone().isBlank();
        if (!hasEmail && !hasPhone) return;

        // fullName is NOT NULL on ClientContact, so fall back to the client's own name.
        String contactName = lead.getContactName() != null && !lead.getContactName().isBlank()
                ? lead.getContactName()
                : client.getClientCompanyName();

        ClientContact contact = ClientContact.builder()
                .client(client)
                .company(companyRef(companyId))
                .fullName(contactName)
                // Normalised on write so this contact is findable by the case-insensitive / digits-only matching duplicate detection uses.
                .email(com.zuhoocms.modules.crm.support.EmailMatching.normalise(lead.getEmail()))
                .phone(com.zuhoocms.modules.crm.support.PhoneMatching.normaliseForStorage(lead.getPhone()))
                .jobTitle(lead.getJobTitle())
                .primaryContact(true)
                .notes("Created automatically when deal was won.")
                .build();

        clientContactRepository.save(contact);
    }

    private Optional<DuplicateMatch> findDuplicateForOpportunity(Opportunity opportunity) {
        Lead sourceLead = opportunity.getSourceLead();
        String companyName = sourceLead != null ? sourceLead.getCompanyName() : null;
        String email = sourceLead != null ? sourceLead.getEmail() : null;
        String phone = sourceLead != null ? sourceLead.getPhone() : null;
        return duplicateDetectionService.findPossibleDuplicateClient(companyName, email, phone);
    }

    // Read-only pre-check so the frontend can show its link-existing / create-new modal before a WON transition, not after.
    @Override
    @Transactional(readOnly = true)
    public DuplicateMatch previewWonDuplicate(Long id) {
        authorizationService.checkPermission(PermissionCode.OPPORTUNITY_VIEW);
        Opportunity opportunity = findOwned(id);
        if (opportunity.getClient() != null) {
            return null;
        }
        return findDuplicateForOpportunity(opportunity).orElse(null);
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }

    /** Reverses creditClientLifetimeValue(); deliberately no {@code .max(BigDecimal.ZERO)} clamp, which let repeated close/reopen ratchet lifetime value upward and hid genuine negatives. */
    private void debitClientLifetimeValue(Opportunity opportunity) {
        if (opportunity.getAmount() == null)
            return;
        adjustLifetimeValue(opportunity.getClient(), opportunity.getAmount().negate());
    }

    /**
     * Applies a signed delta to the client's lifetime value in the database; callers needing the new figure must re-read the client.
     *
     *  - Never touches {@code client.getLifetimeValue()}: the lazy proxy is uninitialised on the reopen/lost path and threw LazyInitializationException.
     *  - Leaving the entity non-dirty is what makes the bulk UPDATE safe, so Hibernate cannot overwrite the computed value at commit.
     */
    private void adjustLifetimeValue(Client client, BigDecimal delta) {
        if (client == null || delta.signum() == 0)
            return;
        clientRepository.adjustLifetimeValue(client.getId(), delta);
    }

    // Filtered in the query, not in Java: findById-then-check loaded another tenant's Employee into the persistence context. Also restricted to still-employed staff, so work is not assigned to leavers.
    private Employee findEmployee(Long employeeId, Long companyId) {
        return employeeRepository.findAssignableByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Employee not found, or is no longer an active employee"));
    }

    private Opportunity findOwned(Long id) {
        return opportunityRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Opportunity not found"));
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }
        return companyId;
    }

    // '!' is the escape character in OpportunityRepository's ESCAPE '!' queries; mirrors GlobalSearchServiceImpl.escapeLikeKeyword.
    private String escapeLikeKeyword(String keyword) {
        if (keyword == null) return null;
        return keyword.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }
}
