package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ServicePrerequisiteServiceImpl implements ServicePrerequisiteService {

    private final ServicePrerequisiteRepository prerequisiteRepository;
    private final CompanyServiceRepository companyServiceRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public ServicePrerequisiteResponse create(Long serviceId, ServicePrerequisiteRequest request) {
        // Prerequisites decide whether a service can be ordered at all, so changing them is a catalogue edit and
        // takes the same code as every other catalogue edit. This class had no AuthorizationService at all, so any
        // employee could add or remove them while both sibling sub-resources - form fields and required documents -
        // check this exact code, and the microservice's own prerequisite service checks it too. The reads below stay
        // open on purpose: ordering a service has to be able to see what it depends on.
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();

        CompanyService service = companyServiceRepository.findByIdAndCompanyId(serviceId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service not found"));

        if (request.getPrerequisiteServiceId().equals(serviceId)) {
            throw new BadRequestException("A service cannot be its own prerequisite");
        }

        CompanyService prerequisiteService = companyServiceRepository
                .findByIdAndCompanyId(request.getPrerequisiteServiceId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Prerequisite service not found"));

        if (prerequisiteRepository.existsByServiceIdAndPrerequisiteServiceId(
                serviceId, prerequisiteService.getId())) {
            throw new BadRequestException(
                    prerequisiteService.getName() + " is already a prerequisite of this service");
        }
        requireNoCycle(companyId, serviceId, prerequisiteService);

        ServicePrerequisite prerequisite = ServicePrerequisite.builder()
                .service(service)
                .prerequisiteService(prerequisiteService)
                .mandatory(request.isMandatory())
                .message(request.getMessage())
                .build();

        prerequisiteRepository.save(prerequisite);
        return ServicePrerequisiteMapper.toResponse(prerequisite);
    }

    @Override
    @Transactional
    public void delete(Long serviceId, Long id) {
        authorizationService.checkPermission(PermissionCode.SERVICE_CATALOG_UPDATE);
        Long companyId = requireCompanyId();
        // Confirms the parent service is in this tenant before touching the row.
        companyServiceRepository.findByIdAndCompanyId(serviceId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service not found"));

        ServicePrerequisite prerequisite = prerequisiteRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Prerequisite not found"));
        if (!prerequisite.getService().getId().equals(serviceId)) {
            throw new ResourceNotFoundException("Prerequisite not found");
        }

        prerequisite.softDelete();
        prerequisiteRepository.save(prerequisite);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ServicePrerequisiteResponse> listByService(Long serviceId) {
        // Resolve the parent service in the caller's tenant: unscoped, any logged-in user could read another company's prerequisite chain by service id.
        CompanyService service = companyServiceRepository.findByIdAndCompanyId(serviceId, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Service not found"));
        return prerequisiteRepository.findByServiceIdOrderByIdAsc(service.getId()).stream()
                .map(ServicePrerequisiteMapper::toResponse)
                .collect(Collectors.toList());
    }

    /**
     * A service requiring itself is already refused, but A requiring B while B requires A leaves both of them
     * permanently un-orderable: each waits on a completed request for the other. Walk the graph from the proposed
     * prerequisite - if it can already reach this service, the new edge would close the loop.
     */
    private void requireNoCycle(Long companyId, Long serviceId, CompanyService prerequisite) {
        Set<Long> seen = new HashSet<>();
        Deque<Long> frontier = new ArrayDeque<>();
        frontier.add(prerequisite.getId());
        seen.add(prerequisite.getId());
        while (!frontier.isEmpty()) {
            List<Long> next = prerequisiteRepository.findPrerequisiteIdsOf(companyId, List.copyOf(frontier));
            frontier.clear();
            for (Long id : next) {
                if (id.equals(serviceId)) {
                    throw new BadRequestException(prerequisite.getName()
                            + " already depends on this service, so making it a prerequisite would leave both"
                            + " services impossible to order");
                }
                if (seen.add(id)) {
                    frontier.add(id);
                }
            }
        }
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
