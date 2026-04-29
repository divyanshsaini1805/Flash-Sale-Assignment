package com.flashsale.engine.model.dto;

import lombok.*;

/**
 * Request DTO for the flash sale endpoint.
 * The client only sends productId and quantity — they have NO knowledge
 * of internal vs external routing. The server decides transparently.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FlashSaleRequest {

    /** Product ID to purchase */
    private Long productId;

    /** Quantity the customer wants to purchase */
    private Integer quantity;
}
