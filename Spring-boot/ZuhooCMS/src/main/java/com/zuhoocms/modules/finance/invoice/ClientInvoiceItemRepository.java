package com.zuhoocms.modules.finance.invoice;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ClientInvoiceItemRepository extends JpaRepository<ClientInvoiceItem, Long> {
}
