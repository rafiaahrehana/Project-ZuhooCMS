package com.zuhoocms.modules.support.category;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SupportCategoryServiceImpl implements SupportCategoryService {

    private static final int MAX_NAME_LENGTH = 200;

    private final SupportCategoryRepository categoryRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public SupportCategoryResponse create(SupportCategoryRequest request) {
        String name = requireName(request);
        if (categoryRepository.existsByCategoryNameIgnoreCase(name)) {
            throw new BadRequestException("Category name already exists: " + name);
        }
        categoryRepository.releaseNameFromDeleted(name);

        SupportCategory category = SupportCategory.builder()
                .categoryName(name)
                .description(request.getDescription())
                .icon(request.getIcon())
                .active(request.isActive())
                .build();

        category = categoryRepository.save(category);
        return SupportCategoryMapper.toResponse(category);
    }

    @Override
    @Transactional(readOnly = true)
    public SupportCategoryResponse getById(Long id) {
        SupportCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        return SupportCategoryMapper.toResponse(category);
    }

    @Override
    @Transactional(readOnly = true)
    public SupportCategoryResponse getByName(String name) {
        SupportCategory category = categoryRepository.findByCategoryName(name)
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        return SupportCategoryMapper.toResponse(category);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportCategoryResponse> getAll(Pageable pageable) {
        checkTenantPermission();
        return categoryRepository.findAll(pageable)
                .map(SupportCategoryMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportCategoryResponse> getActive() {
        checkTenantPermission();
        return categoryRepository.findByActiveTrue()
                .stream()
                .map(SupportCategoryMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public SupportCategoryResponse update(Long id, SupportCategoryRequest request) {
        SupportCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        String name = requireName(request);

        if (!category.getCategoryName().equals(name)) {
            if (categoryRepository.existsByCategoryNameIgnoreCaseAndIdNot(name, id)) {
                throw new BadRequestException("Category name already exists: " + name);
            }
            categoryRepository.releaseNameFromDeleted(name);
        }

        category.setCategoryName(name);
        category.setDescription(request.getDescription());
        category.setIcon(request.getIcon());

        category = categoryRepository.save(category);
        return SupportCategoryMapper.toResponse(category);
    }

    @Override
    @Transactional
    public void updateStatus(Long id, boolean active) {
        SupportCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        category.setActive(active);
        categoryRepository.save(category);
    }

    /** Soft delete that also frees the name: category_name is UNIQUE, so a deleted row keeping it blocks ever recreating that category. */
    @Override
    @Transactional
    public SupportCategoryResponse delete(Long id) {
        SupportCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Category not found"));
        SupportCategoryResponse response = SupportCategoryMapper.toResponse(category);
        category.setCategoryName(truncate(category.getCategoryName()) + "#deleted-" + category.getId());
        category.softDelete();
        categoryRepository.save(category);
        return response;
    }

    private static String requireName(SupportCategoryRequest request) {
        String name = request.getEffectiveName();
        if (name == null || name.isBlank()) {
            throw new BadRequestException("Category name is required");
        }
        if (name.length() > MAX_NAME_LENGTH) {
            throw new BadRequestException("Category name must be at most " + MAX_NAME_LENGTH + " characters");
        }
        return name;
    }

    private static String truncate(String value) {
        return value.length() > MAX_NAME_LENGTH ? value.substring(0, MAX_NAME_LENGTH) : value;
    }

    // Categories are a platform-wide taxonomy: platform staff have no CustomRole and are gated by @PreAuthorize, so only the tenant caller is checked here.
    private void checkTenantPermission() {
        User current = securityUtil.getCurrentUser();
        if (current != null && !current.isPlatformUser()) {
            authorizationService.checkPermission(PermissionCode.SUPPORT_CATEGORY_VIEW);
        }
    }
}
