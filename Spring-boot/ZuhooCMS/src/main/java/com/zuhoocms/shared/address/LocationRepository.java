package com.zuhoocms.shared.address;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface LocationRepository extends JpaRepository<Location, Long> {
    List<Location> findByCountryIdAndParentIsNull(Long countryId);
    List<Location> findByParentId(Long parentId);
    long countByCountryId(Long countryId);
}
