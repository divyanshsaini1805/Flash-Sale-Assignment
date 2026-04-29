package com.flashsale.engine.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * Product entity - represents items in the flash sale inventory.
 */
@Entity
@Table(name = "products")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Product {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    private String description;

    @Column(name = "original_price", nullable = false)
    private Double originalPrice;

    @Column(name = "sale_price", nullable = false)
    private Double salePrice;

    @Column(name = "stock_quantity", nullable = false)
    private Integer stockQuantity;

    private String category;

    @Column(name = "is_flash_sale")
    private Boolean isFlashSale;

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
