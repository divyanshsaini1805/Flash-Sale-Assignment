package com.flashsale.engine.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * ExternalOrderLog entity - stores results from the external workflow.
 * Each processed external request gets logged into this table.
 */
@Entity
@Table(name = "external_order_log")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ExternalOrderLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "product_name", nullable = false)
    private String productName;

    @Column(name = "requested_quantity", nullable = false)
    private Integer requestedQuantity;

    @Column(name = "unit_price", nullable = false)
    private Double unitPrice;

    @Column(name = "total_price", nullable = false)
    private Double totalPrice;

    @Column(nullable = false)
    private String status;

    @Column(name = "execution_time_ms")
    private Long executionTimeMs;

    @Column(name = "processed_at")
    private LocalDateTime processedAt;

    @PrePersist
    protected void onCreate() {
        this.processedAt = LocalDateTime.now();
    }
}
