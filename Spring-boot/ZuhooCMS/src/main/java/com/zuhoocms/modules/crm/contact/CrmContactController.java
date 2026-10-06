package com.zuhoocms.modules.crm.contact;

import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

// Backs the standalone cross-client Contacts page, unlike ClientContactController, which is nested under one Client (/api/clients/{clientId}/contacts).
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/crm/contacts")
public class CrmContactController {

    private final ClientContactService clientContactService;

    @PreAuthorize("hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')")
    @GetMapping
    public ResponseEntity<Page<ClientContactResponse>> listAll(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(clientContactService.listAll(keyword, PageRequest.of(page, size, Sort.by("fullName").ascending())));
    }
}
