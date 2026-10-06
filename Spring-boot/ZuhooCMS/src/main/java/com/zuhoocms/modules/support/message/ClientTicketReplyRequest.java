package com.zuhoocms.modules.support.message;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;
import lombok.NoArgsConstructor;

/** Company staff's reply on a client's CUSTOMER_SUPPORT ticket: the path names the ticket, a ticketId in the body is ignored (as in servicedesk-service), and the reply is always external. */
@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class ClientTicketReplyRequest {

    @NotBlank(message = "Message is required")
    private String message;

    @Size(max = 1000)
    private String attachmentUrl;

    @Size(max = 255)
    private String attachmentFileName;
}
