package com.zuhoocms.modules.servicedesk.dynamicform;

import java.util.List;

public interface ServiceFormFieldService {
    ServiceFormFieldResponse create(Long serviceId, ServiceFormFieldRequest request);
    ServiceFormFieldResponse update(Long serviceId, Long id, ServiceFormFieldRequest request);
    void delete(Long serviceId, Long id);
    List<ServiceFormFieldResponse> listByService(Long serviceId);
}
