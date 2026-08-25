package com.zuhoocms.modules.servicedesk.requestcomment;

import com.zuhoocms.enums.CommentVisibility;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class AddCommentRequest {

    @NotBlank(message = "Comment content is required")
    private String content;

    private CommentVisibility visibility;

    private String attachmentUrl;
}
