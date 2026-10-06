package com.zuhoocms.modules.servicedesk.document;

import com.zuhoocms.modules.servicedesk.companyservice.CompanyService;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class RequiredDocumentServiceImpl implements RequiredDocumentService {

    private final RequiredDocumentRepository requiredDocumentRepository;
    private final CompanyServiceRepository companyServiceRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public RequiredDocumentResponse create(Long serviceId, RequiredDocumentRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();

        CompanyService service = companyServiceRepository.findByIdAndCompanyId(serviceId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service not found"));

        RequiredDocument doc = RequiredDocument.builder()
                .company(service.getCompany())
                .service(service)
                .docName(request.getDocName())
                .description(request.getDescription())
                .mandatory(Boolean.TRUE.equals(request.getMandatory()))
                .maxAgeDays(request.getMaxAgeDays())
                .allowedFormats(request.getAllowedFormats())
                // Boxed now, and the column is a primitive, so an omitted key takes the entity's own default
                // rather than unboxing null.
                .sortOrder(request.getSortOrder() != null ? request.getSortOrder() : 0)
                .build();

        requiredDocumentRepository.save(doc);
        return RequiredDocumentMapper.toResponse(doc);
    }

    @Override
    @Transactional
    public RequiredDocumentResponse update(Long serviceId, Long id, RequiredDocumentRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();

        RequiredDocument doc = findDocOfService(serviceId, id, companyId);

        if (request.getDocName() != null) doc.setDocName(request.getDocName());
        if (request.getDescription() != null) doc.setDescription(request.getDescription());
        // Guarded: as a primitive, an update that omitted it silently made a required document optional.
        if (request.getMandatory() != null) doc.setMandatory(request.getMandatory());
        if (request.getMaxAgeDays() != null) doc.setMaxAgeDays(request.getMaxAgeDays());
        if (request.getAllowedFormats() != null) doc.setAllowedFormats(request.getAllowedFormats());
        // Guarded like its neighbours. Unconditional and primitive, an update that omitted the key sent 0 and
        // moved the document to the front, reordering the list as a side effect of renaming one entry.
        if (request.getSortOrder() != null) doc.setSortOrder(request.getSortOrder());

        requiredDocumentRepository.save(doc);
        return RequiredDocumentMapper.toResponse(doc);
    }

    @Override
    @Transactional
    public void delete(Long serviceId, Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();
        RequiredDocument doc = findDocOfService(serviceId, id, companyId);

        doc.softDelete();
        requiredDocumentRepository.save(doc);
    }

    @Override
    // Deliberately ungated, matching servicedesk-service: anybody ordering a service has to be able to read what
    // it will ask them for, including a CLIENT who holds no catalogue permission at all. The three writes above
    // check SERVICE_CATALOG_UPDATE - before this, nothing checked anything and any employee could rewrite them.
    @Transactional(readOnly = true)
    public List<RequiredDocumentResponse> listByService(Long serviceId) {
        Long companyId = requireCompanyId();
        return requiredDocumentRepository.findByCompanyIdAndServiceIdOrderBySortOrderAsc(companyId, serviceId).stream()
                .filter(d -> !d.isDeleted())
                .map(RequiredDocumentMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** The document requirement must belong to the service in the path, not merely to the same company. */
    private RequiredDocument findDocOfService(Long serviceId, Long id, Long companyId) {
        RequiredDocument doc = requiredDocumentRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Required document not found"));
        if (doc.getService() == null || !doc.getService().getId().equals(serviceId)) {
            throw new ResourceNotFoundException("Required document not found");
        }
        return doc;
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
