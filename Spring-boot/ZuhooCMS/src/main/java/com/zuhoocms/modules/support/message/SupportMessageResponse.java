package com.zuhoocms.modules.support.message;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
// Lombok's isInternal()/isResolution() would also emit "internal"/"resolution"; only the "is" keys pinned below are part of the contract.
@JsonIgnoreProperties({"internal", "resolution"})
public class SupportMessageResponse {
    private Long id;
    private Long ticketId;
    private Long sentById;
    private String sentByName;
    private String message;
    private String messageType;
    @JsonProperty("isInternal")
    private boolean isInternal;
    private String attachmentUrl;
    private String attachmentFileName;
    private Long attachmentSize;
    @JsonProperty("isResolution")
    private boolean isResolution;
    private LocalDateTime createdAt;
}
