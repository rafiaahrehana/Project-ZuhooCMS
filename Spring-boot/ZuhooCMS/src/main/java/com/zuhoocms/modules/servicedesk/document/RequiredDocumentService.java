package com.zuhoocms.modules.servicedesk.document;

import java.util.List;

public interface RequiredDocumentService {
    RequiredDocumentResponse create(Long serviceId, RequiredDocumentRequest request);
    RequiredDocumentResponse update(Long serviceId, Long id, RequiredDocumentRequest request);
    void delete(Long serviceId, Long id);
    List<RequiredDocumentResponse> listByService(Long serviceId);
}
