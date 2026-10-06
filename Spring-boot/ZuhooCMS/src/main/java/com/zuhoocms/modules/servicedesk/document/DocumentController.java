package com.zuhoocms.modules.servicedesk.document;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/** Open to any authenticated tenant user (owning client or staff), the same pattern as comments/tasks on ServiceRequestController. */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/service-requests/{requestId}/documents")
public class DocumentController {

    private final DocumentService documentService;

    @PostMapping
    public ResponseEntity<DocumentResponse> upload(
            @PathVariable Long requestId,
            @Valid @RequestBody CreateDocumentRequest request) {
        return new ResponseEntity<>(documentService.upload(requestId, request), HttpStatus.CREATED);
    }

    @GetMapping
    public ResponseEntity<List<DocumentResponse>> list(@PathVariable Long requestId) {
        return ResponseEntity.ok(documentService.listForRequest(requestId));
    }

    @DeleteMapping("/{documentId}")
    public ResponseEntity<Void> delete(@PathVariable Long requestId, @PathVariable Long documentId) {
        documentService.delete(requestId, documentId);
        return ResponseEntity.noContent().build();
    }
}
