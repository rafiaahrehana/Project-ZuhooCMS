package com.zuhoocms.modules.servicedesk.requestcomment;

import com.zuhoocms.enums.CommentVisibility;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RequestCommentRepository extends JpaRepository<RequestComment, Long> {

    Page<RequestComment> findByServiceRequestIdOrderByCreatedAtDesc(
        Long serviceRequestId, Pageable pageable);

    Page<RequestComment> findByServiceRequestIdAndVisibilityOrderByCreatedAtDesc(
        Long serviceRequestId, CommentVisibility visibility, Pageable pageable);
}
