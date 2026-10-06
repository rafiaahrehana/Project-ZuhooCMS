package com.zuhoocms.modules.search;

import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.SearchAnswerPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.lead.Lead;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.modules.crm.opportunity.Opportunity;
import com.zuhoocms.modules.crm.opportunity.OpportunityRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.support.ticket.SupportTicket;
import com.zuhoocms.modules.support.ticket.SupportTicketRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.modules.finance.invoice.Refund;
import com.zuhoocms.modules.finance.invoice.RefundRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import com.zuhoocms.modules.ai.support.AiTransactionBoundary;

import org.springframework.data.domain.Page;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class GlobalSearchServiceImpl implements GlobalSearchService {

    private static final int PER_TYPE_LIMIT = 10;

    private final LeadRepository leadRepository;
    private final ClientRepository clientRepository;
    private final OpportunityRepository opportunityRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final SupportTicketRepository supportTicketRepository;
    private final ClientInvoiceRepository invoiceRepository;
    private final RefundRepository refundRepository;
    private final AiService aiService;
    private final AiTransactionBoundary aiTx;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    public GlobalSearchResponse search(String query) {
        Long companyId = requireCompanyId();
        if (query == null || query.trim().length() < 2) {
            throw new BadRequestException("Search query must be at least 2 characters");
        }
        String raw = query.trim();
        GlobalSearchResponse response = new GlobalSearchResponse();
        // The raw query, not the LIKE-escaped form (which leaked "!_" back to the UI).
        response.setQuery(raw);
        response.setTotalMatches(collect(companyId, raw, response.getResults()));
        return response;
    }

    /** Runs every category the caller may see for one term; returns the total match count. */
    private long collect(Long companyId, String raw, List<SearchResultItem> results) {
        // Only the hand-written LIKE ... ESCAPE '!' queries take the escaped term; derived *Containing* queries escape themselves, so "a_b" would become a literal "a!_b".
        String keyword = escapeLikeKeyword(raw);
        Pageable top = PageRequest.of(0, PER_TYPE_LIMIT);
        long totalMatches = 0;

        // Gate each category on the same PermissionCode its own endpoints use, or search leaks invoice amounts and ticket contents to an employee without those grants.
        // A missing permission omits the category rather than failing the whole mixed-type search.
        if (authorizationService.hasPermission(PermissionCode.LEAD_VIEW)) {
            Page<Lead> leadPage = leadRepository.searchLeads(companyId, keyword, top);
            totalMatches += leadPage.getTotalElements();
            leadPage.forEach(lead -> results.add(new SearchResultItem("LEAD", lead.getId(),
                    lead.getContactName(),
                    (lead.getCompanyName() != null ? lead.getCompanyName() + " · " : "") + lead.getStatus(),
                    "/crm/leads")));
        }

        if (authorizationService.hasPermission(PermissionCode.CLIENT_VIEW)) {
            Page<Client> clientPage = clientRepository.searchClients(companyId, keyword, top);
            totalMatches += clientPage.getTotalElements();
            clientPage.forEach(client -> results.add(new SearchResultItem("CLIENT", client.getId(),
                    client.getClientCompanyName() != null ? client.getClientCompanyName()
                            : client.getUser().getFirstName() + " " + client.getUser().getLastName(),
                    client.getIndustry() != null ? client.getIndustry() : "Account",
                    "/crm/clients/" + client.getId())));
        }

        if (authorizationService.hasPermission(PermissionCode.OPPORTUNITY_VIEW)) {
            Page<Opportunity> oppPage = opportunityRepository.searchOpportunities(companyId, keyword, top);
            totalMatches += oppPage.getTotalElements();
            oppPage.forEach(opp -> results.add(new SearchResultItem("OPPORTUNITY", opp.getId(),
                    opp.getName(),
                    opp.getStage() + (opp.getAmount() != null ? " · " + opp.getAmount() : ""),
                    "/crm/pipeline")));
        }

        if (authorizationService.hasPermission(PermissionCode.SERVICE_REQUEST_VIEW)) {
            Page<ServiceRequest> srPage = serviceRequestRepository.findByCompanyIdAndTitleContainingIgnoreCaseAndDeletedFalse(companyId, raw, top);
            totalMatches += srPage.getTotalElements();
            srPage.forEach(sr -> results.add(new SearchResultItem("SERVICE_REQUEST", sr.getId(),
                    sr.getTitle(), String.valueOf(sr.getStatus()),
                    "/servicedesk/requests/" + sr.getId())));
        }

        if (authorizationService.hasPermission(PermissionCode.TICKET_VIEW)) {
            Page<SupportTicket> ticketPage = supportTicketRepository.findByCompanyIdAndTitleContainingIgnoreCase(companyId, raw, top);
            totalMatches += ticketPage.getTotalElements();
            ticketPage.forEach(ticket -> results.add(new SearchResultItem("TICKET", ticket.getId(),
                    ticket.getTitle(),
                    ticket.getTicketNumber() + " · " + ticket.getStatus(),
                    "/support/tickets")));
        }

        if (authorizationService.hasPermission(PermissionCode.INVOICE_VIEW)) {
            Page<ClientInvoice> invoicePage = invoiceRepository.findByCompanyIdAndInvoiceNumberContainingIgnoreCase(companyId, raw, top);
            totalMatches += invoicePage.getTotalElements();
            invoicePage.forEach(invoice -> results.add(new SearchResultItem("INVOICE", invoice.getId(),
                    invoice.getInvoiceNumber(),
                    invoice.getStatus() + " · " + invoice.getTotalAmount(),
                    "/finance/invoices")));

            // No REFUND_VIEW code exists; ClientInvoiceServiceImpl.listRefunds() also gates refunds on INVOICE_VIEW.
            Page<Refund> refundPage = refundRepository.searchRefunds(companyId, keyword, top);
            totalMatches += refundPage.getTotalElements();
            refundPage.forEach(refund -> results.add(new SearchResultItem("REFUND", refund.getId(),
                    "Refund · " + refund.getClientInvoice().getInvoiceNumber(),
                    refund.getStatus() + " · " + refund.getRequestedAmount(),
                    "/finance/refunds")));
        }

        return totalMatches;
    }

    /** Words that carry no search signal in a natural-language question. */
    private static final java.util.Set<String> STOP_WORDS = java.util.Set.of(
            "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "from", "by",
            "with", "about", "into", "over", "is", "are", "was", "were", "be", "been", "being", "am",
            "do", "does", "did", "have", "has", "had", "can", "could", "should", "would", "will",
            "shall", "may", "might", "must", "what", "which", "who", "whom", "whose", "when", "where",
            "why", "how", "this", "that", "these", "those", "there", "here", "it", "its", "i", "me",
            "my", "we", "our", "us", "you", "your", "he", "she", "they", "them", "their", "his", "her",
            "any", "all", "some", "many", "much", "more", "most", "no", "not", "yes", "please", "show",
            "find", "list", "give", "tell", "get", "search", "look", "up", "if", "so", "than", "then",
            "also", "just", "only", "as", "per", "let", "know", "want", "need", "see", "status");

    /** Max distinct terms searched per question - bounds the query fan-out. */
    private static final int MAX_ASK_TERMS = 5;

    /** Significant terms of a question: split on non letter/digit/-/_, drop stop-words and one-letter tokens, de-duplicate, keep order. */
    static List<String> extractKeywords(String question) {
        java.util.LinkedHashSet<String> terms = new java.util.LinkedHashSet<>();
        for (String token : question.split("[^\\p{L}\\p{N}_\\-]+")) {
            String t = token.trim();
            t = t.replaceAll("^[-_]+|[-_]+$", "");
            if (t.length() < 2) continue;
            if (STOP_WORDS.contains(t.toLowerCase(java.util.Locale.ROOT))) continue;
            terms.add(t);
            if (terms.size() >= MAX_ASK_TERMS) break;
        }
        return new java.util.ArrayList<>(terms);
    }

    /** Searches each significant term of the question and merges the hits (de-duplicated by type+id). */
    private GlobalSearchResponse searchQuestion(String question) {
        Long companyId = requireCompanyId();
        GlobalSearchResponse merged = new GlobalSearchResponse();
        merged.setQuery(question == null ? "" : question.trim());
        if (question == null || question.isBlank()) {
            return merged;
        }
        List<String> terms = extractKeywords(question);
        if (terms.isEmpty() && question.trim().length() >= 2) {
            terms = List.of(question.trim());
        }
        java.util.Map<String, SearchResultItem> byKey = new java.util.LinkedHashMap<>();
        long total = 0;
        for (String term : terms) {
            List<SearchResultItem> hits = new java.util.ArrayList<>();
            total += collect(companyId, term, hits);
            for (SearchResultItem hit : hits) {
                byKey.putIfAbsent(hit.getType() + ":" + hit.getId(), hit);
            }
        }
        merged.getResults().addAll(byKey.values());
        merged.setTotalMatches(Math.max(byKey.size(), 0));
        return merged;
    }

    // NOT_SUPPORTED overrides this class's @Transactional so the provider call isn't inside a transaction - see AiTransactionBoundary.
    @Override
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public AskResponse ask(AskRequest request) {
        // Self-invocation gets no transaction of its own, so load() keeps the repository reads in one that commits before the AI call.
        // A whole sentence as one LIKE term matches nothing, so search each significant keyword and merge.
        GlobalSearchResponse searchResults = aiTx.load(() -> searchQuestion(request.getQuestion()));

        if (searchResults.getResults().isEmpty()) {
            AskResponse response = new AskResponse();
            response.setQuestion(request.getQuestion());
            response.setAnswer("No matching records found. Try a different search term.");
            response.setSources(List.of());
            return response;
        }

        StringBuilder context = new StringBuilder();
        for (SearchResultItem item : searchResults.getResults()) {
            context.append("- [").append(item.getType()).append("] ")
                    .append(item.getTitle()).append(" (").append(item.getSubtitle()).append(")\n");
        }

        String prompt = SearchAnswerPromptBuilder.builder()
                .setQuestion(request.getQuestion())
                .setContext(context.isEmpty() ? null : context.toString())
                .build();

        String answer;
        try {
            answer = aiService.generateRaw(AiFeature.SEARCH_ANSWER, prompt);
        } catch (com.zuhoocms.modules.ai.exception.AiProviderException ex) {
            // The matching records are still useful without the AI summary.
            answer = "The AI assistant is unavailable right now - here are the matching records.";
        }

        AskResponse response = new AskResponse();
        response.setQuestion(request.getQuestion());
        response.setAnswer(answer);
        response.setSources(searchResults.getResults());
        return response;
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for current platformuser");
        }
        return companyId;
    }

    /** '!' is the LIKE escape character (ESCAPE '!'): a backslash cannot be used, since in an HQL literal it escapes the closing quote and swallows the rest of the OR-chain. */
    private String escapeLikeKeyword(String keyword) {
        return keyword.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }
}
