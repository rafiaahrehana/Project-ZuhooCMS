package com.zuhoocms.modules.servicedesk.companyservice;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository
public interface ServicePrerequisiteRepository extends JpaRepository<ServicePrerequisite, Long> {
    List<ServicePrerequisite> findByServiceIdOrderByIdAsc(Long serviceId);

    boolean existsByServiceIdAndPrerequisiteServiceId(Long serviceId, Long prerequisiteServiceId);

    /** One hop of the prerequisite graph, used to walk it when checking for a cycle. */
    @Query("""
            SELECT p.prerequisiteService.id FROM ServicePrerequisite p
            WHERE p.service.company.id = :companyId AND p.service.id IN :serviceIds
            """)
    List<Long> findPrerequisiteIdsOf(@Param("companyId") Long companyId,
                                     @Param("serviceIds") Collection<Long> serviceIds);
}
