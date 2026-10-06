package com.zuhoocms.modules.servicedesk.dynamicform;

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
public class ServiceFormFieldServiceImpl implements ServiceFormFieldService {

    private final ServiceFormFieldRepository formFieldRepository;
    private final CompanyServiceRepository companyServiceRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public ServiceFormFieldResponse create(Long serviceId, ServiceFormFieldRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();

        CompanyService service = companyServiceRepository.findByIdAndCompanyId(serviceId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service not found"));

        ServiceFormField field = ServiceFormField.builder()
                .company(service.getCompany())
                .service(service)
                .label(request.getLabel())
                .fieldType(request.getFieldType())
                .required(Boolean.TRUE.equals(request.getRequired()))
                .validationRules(request.getValidationRules())
                // Boxed now, and the column is a primitive, so an omitted key takes the entity's own default
                // rather than unboxing null.
                .sortOrder(request.getSortOrder() != null ? request.getSortOrder() : 0)
                .build();

        formFieldRepository.save(field);
        return ServiceFormFieldMapper.toResponse(field);
    }

    @Override
    @Transactional
    public ServiceFormFieldResponse update(Long serviceId, Long id, ServiceFormFieldRequest request) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();

        ServiceFormField field = findFieldOfService(serviceId, id, companyId);

        if (request.getLabel() != null) field.setLabel(request.getLabel());
        if (request.getFieldType() != null) field.setFieldType(request.getFieldType());
        // Guarded: as a primitive, an update that omitted it silently made a required question optional.
        if (request.getRequired() != null) field.setRequired(request.getRequired());
        if (request.getValidationRules() != null) field.setValidationRules(request.getValidationRules());
        // Guarded like its neighbours. Unconditional and primitive, an update that omitted the key sent 0 and
        // moved the field to the front, reordering the whole form as a side effect of renaming one label.
        if (request.getSortOrder() != null) field.setSortOrder(request.getSortOrder());

        formFieldRepository.save(field);
        return ServiceFormFieldMapper.toResponse(field);
    }

    @Override
    @Transactional
    public void delete(Long serviceId, Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();
        ServiceFormField field = findFieldOfService(serviceId, id, companyId);
        
        field.softDelete();
        formFieldRepository.save(field);
    }

    @Override
    // Deliberately ungated, matching servicedesk-service: anybody ordering a service has to be able to read what
    // it will ask them for, including a CLIENT who holds no catalogue permission at all. The three writes above
    // check SERVICE_CATALOG_UPDATE - before this, nothing checked anything and any employee could rewrite them.
    @Transactional(readOnly = true)
    public List<ServiceFormFieldResponse> listByService(Long serviceId) {
        Long companyId = requireCompanyId();
        return formFieldRepository.findByCompanyIdAndServiceIdOrderBySortOrderAsc(companyId, serviceId).stream()
                .filter(f -> !f.isDeleted())
                .map(ServiceFormFieldMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** The field must belong to the service in the path, not merely to the same company. */
    private ServiceFormField findFieldOfService(Long serviceId, Long id, Long companyId) {
        ServiceFormField field = formFieldRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Form field not found"));
        if (field.getService() == null || !field.getService().getId().equals(serviceId)) {
            throw new ResourceNotFoundException("Form field not found");
        }
        return field;
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
