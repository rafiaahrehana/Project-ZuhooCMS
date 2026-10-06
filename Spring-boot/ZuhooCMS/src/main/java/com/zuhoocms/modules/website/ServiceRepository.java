package com.zuhoocms.modules.website;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface ServiceRepository extends JpaRepository<Service, Long> {
    List<Service> findByCompanyIdOrderByIdAsc(Long companyId);
    Optional<Service> findBySlugAndCompanyId(String slug, Long companyId);
    List<Service> findByCompanyIdAndCategoryNameIgnoreCaseOrderByIdAsc(Long companyId, String categoryName);
    // Parameter order must follow the method name (companyId, then title), or the search text binds to company_id and every ?q= 500s.
    List<Service> findByCompanyIdAndTitleContainingIgnoreCaseOrderByIdAsc(Long companyId, String title);
}
