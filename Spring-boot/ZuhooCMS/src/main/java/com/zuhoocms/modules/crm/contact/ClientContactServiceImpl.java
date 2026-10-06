package com.zuhoocms.modules.crm.contact;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class ClientContactServiceImpl implements ClientContactService {

    private final ClientContactRepository clientContactRepository;
    private final ClientRepository clientRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    public ClientContactResponse create(Long clientId, ClientContactRequest request) {
        authorizationService.checkPermission(PermissionCode.CONTACT_CREATE);
        Long companyId = requireCompanyId();
        Client client = clientRepository.findByIdAndCompanyId(clientId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Client not found"));

        // Normalised before the check and the write, so duplicate detection's case-insensitive email and digits-only phone lookups both find it.
        String email = com.zuhoocms.modules.crm.support.EmailMatching.normalise(request.getEmail());
        String phone = com.zuhoocms.modules.crm.support.PhoneMatching.normaliseForStorage(request.getPhone());

        if (email != null
            && clientContactRepository.existsByEmailForClient(email, clientId, companyId, null)) {
            throw new BadRequestException("A contact with this email already exists for this client");
        }

        boolean primary = Boolean.TRUE.equals(request.getPrimaryContact());
        if (primary) {
            clientContactRepository.clearPrimaryContact(clientId, companyId);
        }

        ClientContact contact = ClientContact.builder()
            .fullName(request.getFullName())
            .email(email)
            .phone(phone)
            .jobTitle(request.getJobTitle())
            .department(request.getDepartment())
            .primaryContact(primary)
            .notes(request.getNotes())
            .client(client)
            .company(client.getCompany())
            .build();

        return ClientContactMapper.toResponse(clientContactRepository.save(contact));
    }

    @Override
    @Transactional(readOnly = true)
    public List<ClientContactResponse> listByClient(Long clientId) {
        authorizationService.checkPermission(PermissionCode.CONTACT_VIEW);
        Long companyId = requireCompanyId();
        clientRepository.findByIdAndCompanyId(clientId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Client not found"));
        return clientContactRepository
            .findByClientIdAndCompanyIdOrderByPrimaryContactDescCreatedAtDesc(clientId, companyId)
            .stream()
            .map(ClientContactMapper::toResponse)
            .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ClientContactResponse> listAll(String keyword, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.CONTACT_VIEW);
        Long companyId = requireCompanyId();
        // fullName is not unique, so without the id ASC tiebreaker Postgres orders ties differently per page request and a contact appears twice or not at all.
        Pageable paged = com.zuhoocms.modules.crm.support.CrmSortWhitelist.withIdTiebreaker(pageable);
        Page<ClientContact> page = keyword != null && !keyword.isBlank()
                ? clientContactRepository.searchContacts(companyId, escapeLikeKeyword(keyword.trim()), paged)
                : clientContactRepository.findByCompanyId(companyId, paged);
        return page.map(ClientContactMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public ClientContactResponse getById(Long clientId, Long id) {
        // Its list siblings check CONTACT_VIEW; unguarded, this single-row read was the way around them.
        authorizationService.checkPermission(PermissionCode.CONTACT_VIEW);
        return ClientContactMapper.toResponse(findOwned(clientId, id));
    }

    @Override
    public ClientContactResponse update(Long clientId, Long id, ClientContactRequest request) {
        authorizationService.checkPermission(PermissionCode.CONTACT_UPDATE);
        ClientContact contact = findOwned(clientId, id);
        Long companyId = requireCompanyId();

        String email = com.zuhoocms.modules.crm.support.EmailMatching.normalise(request.getEmail());
        String phone = com.zuhoocms.modules.crm.support.PhoneMatching.normaliseForStorage(request.getPhone());

        // update() skipped the email uniqueness create() enforces, so one client could hold two contacts with the same email and duplicate detection picked either.
        if (email != null && !email.equalsIgnoreCase(contact.getEmail())
            && clientContactRepository.existsByEmailForClient(email, contact.getClient().getId(), companyId, id)) {
            throw new BadRequestException("A contact with this email already exists for this client");
        }

        // Null-skipped: assigned unconditionally, a fullName-only PATCH from the contact list erased the email duplicate detection matches on.
        if (request.getFullName() != null) contact.setFullName(request.getFullName());
        if (email != null) contact.setEmail(email);
        if (phone != null) contact.setPhone(phone);
        if (request.getJobTitle() != null) contact.setJobTitle(request.getJobTitle());
        if (request.getDepartment() != null) contact.setDepartment(request.getDepartment());
        if (request.getNotes() != null) contact.setNotes(request.getNotes());

        if (Boolean.TRUE.equals(request.getPrimaryContact()) && !contact.isPrimaryContact()) {
            clientContactRepository.clearPrimaryContact(contact.getClient().getId(), companyId);
            contact.setPrimaryContact(true);
        }

        return ClientContactMapper.toResponse(clientContactRepository.save(contact));
    }

    @Override
    public ClientContactResponse markPrimary(Long clientId, Long id) {
        authorizationService.checkPermission(PermissionCode.CONTACT_UPDATE);
        ClientContact contact = findOwned(clientId, id);
        clientContactRepository.clearPrimaryContact(contact.getClient().getId(), requireCompanyId());
        contact.setPrimaryContact(true);
        return ClientContactMapper.toResponse(clientContactRepository.save(contact));
    }

    @Override
    public void delete(Long clientId, Long id) {
        authorizationService.checkPermission(PermissionCode.CONTACT_DELETE);
        ClientContact contact = findOwned(clientId, id);
        contact.softDelete();
        clientContactRepository.save(contact);
    }

    private ClientContact findOwned(Long clientId, Long id) {
        ClientContact contact = clientContactRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Contact not found"));
        if (!contact.getClient().getId().equals(clientId)) {
            throw new ResourceNotFoundException("Contact not found");
        }
        return contact;
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }
        return companyId;
    }

    // '!' is the escape character in ClientContactRepository's ESCAPE '!' queries; mirrors GlobalSearchServiceImpl.escapeLikeKeyword.
    private String escapeLikeKeyword(String keyword) {
        if (keyword == null) return null;
        return keyword.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }
}
