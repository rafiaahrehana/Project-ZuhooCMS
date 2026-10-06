package com.zuhoocms.modules.crm.tag;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class TagServiceImpl implements TagService {

    private final TagRepository tagRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional(readOnly = true)
    public List<TagResponse> list() {
        authorizationService.checkPermission(PermissionCode.TAG_VIEW);
        return TagMapper.toResponseList(tagRepository.findByCompanyIdOrderByNameAsc(requireCompanyId()));
    }

    @Override
    public TagResponse create(TagRequest request) {
        authorizationService.checkPermission(PermissionCode.TAG_MANAGE);
        Long companyId = requireCompanyId();
        requireNameAvailable(request.getName(), companyId, null);
        Tag tag = Tag.builder()
                .name(request.getName().trim())
                .color(request.getColor())
                .company(companyRef(companyId))
                .build();
        return TagMapper.toResponse(tagRepository.save(tag));
    }

    @Override
    public TagResponse update(Long id, TagRequest request) {
        authorizationService.checkPermission(PermissionCode.TAG_MANAGE);
        Long companyId = requireCompanyId();
        Tag tag = findOwned(id);
        if (request.getName() != null) {
            // update() skipped the check create() does, so a rename onto an existing name hit the database as an opaque 409; excluding this row keeps renaming a tag to its own name working.
            requireNameAvailable(request.getName(), companyId, id);
            tag.setName(request.getName().trim());
        }
        if (request.getColor() != null) tag.setColor(request.getColor());
        return TagMapper.toResponse(tagRepository.save(tag));
    }

    /** Case-insensitive, live tags only, excluding the row being edited, so it agrees with the partial unique index in CrmSchemaMigrationRunner about what is a collision. */
    private void requireNameAvailable(String name, Long companyId, Long excludeId) {
        if (name == null || name.isBlank()) return;
        if (tagRepository.existsByNameIgnoringCase(name.trim(), companyId, excludeId)) {
            throw new BadRequestException("A tag named \"" + name.trim() + "\" already exists");
        }
    }

    @Override
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.TAG_MANAGE);
        Tag tag = findOwned(id);
        tag.softDelete();
        tagRepository.save(tag);
    }

    private Tag findOwned(Long id) {
        return tagRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Tag not found: " + id));
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context found");
        }
        return companyId;
    }
}
