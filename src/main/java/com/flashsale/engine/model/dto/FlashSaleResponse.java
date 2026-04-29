package com.flashsale.engine.model.dto;

import lombok.*;

/**
 * Response DTO returned to the client after processing a flash sale request.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FlashSaleResponse {

    private String workflow;
    private String productName;
    private Integer requestedQuantity;
    private Double unitPrice;
    private Double totalPrice;
    private Integer remainingStock;
    private String status;
    private String message;
    private String outputDestination;
    private Long executionTimeMs;
}
