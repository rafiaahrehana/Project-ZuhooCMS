package com.zuhoocms.modules.crm.duplicate;

import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.contact.ClientContact;
import com.zuhoocms.modules.crm.contact.ClientContactRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/** Nudge-not-block duplicate detection on company name / email / phone / domain, using normalized exact/LIKE matching rather than introducing pg_trgm for the one case. */
@Slf4j
@Service
@RequiredArgsConstructor
public class DuplicateDetectionService {

    private final ClientRepository clientRepository;
    private final ClientContactRepository clientContactRepository;
    private final SecurityUtil securityUtil;

    @Transactional(readOnly = true)
    public Optional<DuplicateMatch> findPossibleDuplicateClient(String companyName, String email, String phone) {
        Long companyId = requireCompanyId();

        if (companyName != null && !companyName.isBlank()) {
            Optional<Client> byName = clientRepository
                    .findFirstByClientCompanyNameIgnoreCaseAndCompanyIdAndDeletedFalse(companyName.trim(), companyId);
            if (byName.isPresent()) {
                return byName.map(c -> new DuplicateMatch(c.getId(), c.getClientCompanyName(), "company name"));
            }
        }

        if (email != null && !email.isBlank()) {
            Optional<ClientContact> byEmail = clientContactRepository
                    .findFirstByEmailIgnoreCaseAndCompanyIdAndDeletedFalse(email.trim(), companyId);
            Optional<DuplicateMatch> emailMatch = toMatch(byEmail, "email");
            if (emailMatch.isPresent()) {
                return emailMatch;
            }

            String domain = extractDomain(email);
            if (domain != null) {
                List<Client> byDomain = clientRepository.findByWebsiteContainingDomain(companyId, domain);
                if (!byDomain.isEmpty()) {
                    Client c = byDomain.get(0);
                    return Optional.of(new DuplicateMatch(c.getId(), c.getClientCompanyName(), "domain"));
                }
            }
        }

        // Digits-only, not raw string equality: "+966 50 123 4567" and "0501234567" are one person.
        String phoneKey = com.zuhoocms.modules.crm.support.PhoneMatching.matchKey(phone);
        if (phoneKey != null) {
            Optional<ClientContact> byPhone = clientContactRepository
                    .findFirstByNormalisedPhone(phoneKey, companyId);
            Optional<DuplicateMatch> phoneMatch = toMatch(byPhone, "phone");
            if (phoneMatch.isPresent()) {
                return phoneMatch;
            }
        }

        return Optional.empty();
    }

    /** Turns a matched contact into a DuplicateMatch, skipping unresolvable clients: {@code contact.getClient()} for a contact orphaned by a soft-deleted client threw EntityNotFoundException, surfacing as a 500 or a 404 "Client not found" while marking an unrelated deal Won. */
    private Optional<DuplicateMatch> toMatch(Optional<ClientContact> contact, String reason) {
        if (contact.isEmpty()) {
            return Optional.empty();
        }
        try {
            Client client = contact.get().getClient();
            if (client == null || client.isDeleted()) {
                return Optional.empty();
            }
            return Optional.of(new DuplicateMatch(client.getId(), client.getClientCompanyName(), reason));
        } catch (jakarta.persistence.EntityNotFoundException
                 | org.hibernate.ObjectNotFoundException ex) {
            log.warn("Duplicate-detection contact {} points at a client that no longer resolves - ignoring",
                    contact.get().getId());
            return Optional.empty();
        }
    }

    private String extractDomain(String email) {
        int at = email.indexOf('@');
        if (at < 0 || at == email.length() - 1) return null;
        return email.substring(at + 1).trim().toLowerCase();
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context found");
        }
        return companyId;
    }
}
