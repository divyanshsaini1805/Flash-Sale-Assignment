package com.flashsale.engine.service;

import com.flashsale.engine.model.ExternalOrderLog;
import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.repository.ExternalOrderLogRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * External Workflow Service — the FALLBACK path.
 * ------------------------------------------------
 * Used when the circuit breaker is OPEN (DB is unhealthy/overloaded).
 *
 * Maintains a pre-warmed in-memory cache of product data (simulating
 * a Redis/CDN cache that would exist in a real flash sale system).
 * This allows the system to keep serving customers even when the DB is down.
 *
 * Sink: persists results into the external_order_log table.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ExternalWorkflowService {

    private final ExternalOrderLogRepository externalOrderLogRepository;

    /**
     * Pre-warmed product cache: productId -> [name, price, stock]
     * In a real system, this would be populated from Redis or a cache warmup
     * job before the flash sale starts.
     */
    private final Map<Long, CachedProduct> productCache = new ConcurrentHashMap<>(Map.of(
            1L, new CachedProduct("iPhone 15 Pro", 899.99, 50),
            2L, new CachedProduct("Sony WH-1000XM5", 249.99, 200),
            3L, new CachedProduct("Nike Air Max 90", 79.99, 500),
            4L, new CachedProduct("Samsung 65\" OLED TV", 1199.99, 30),
            5L, new CachedProduct("Dyson V15 Detect", 499.99, 100),
            6L, new CachedProduct("Instant Pot Duo 7-in-1", 49.99, 300),
            7L, new CachedProduct("Apple Watch Series 9", 329.99, 150),
            8L, new CachedProduct("Levi's 501 Original Jeans", 39.99, 400),
            9L, new CachedProduct("Kindle Paperwhite", 94.99, 250),
            10L, new CachedProduct("Lodge Cast Iron Skillet", 24.99, 600)
    ));

    /**
     * Simple record to hold cached product data.
     */
    private record CachedProduct(String name, double price, int stock) {}

    /**
     * Process the order from the in-memory cache (no DB involved).
     * This is the fallback when the circuit breaker is open.
     */
    public FlashSaleResponse process(FlashSaleRequest request) {
        Long productId = request.getProductId();
        int quantity = request.getQuantity();
        log.info("[EXTERNAL/FALLBACK] Processing order for productId={}, qty={}", productId, quantity);

        // 1. Check if product exists in cache
        CachedProduct cached = productCache.get(productId);
        if (cached == null) {
            return FlashSaleResponse.builder()
                    .workflow("EXTERNAL")
                    .productName("Unknown (ID: " + productId + ")")
                    .requestedQuantity(quantity)
                    .unitPrice(0.0)
                    .totalPrice(0.0)
                    .remainingStock(0)
                    .status("FAILED")
                    .message("Product not found in fallback cache for ID: " + productId)
                    .outputDestination("DB: external_order_log")
                    .build();
        }

        // 2. Check stock in cache
        if (cached.stock() < quantity) {
            return FlashSaleResponse.builder()
                    .workflow("EXTERNAL")
                    .productName(cached.name())
                    .requestedQuantity(quantity)
                    .unitPrice(cached.price())
                    .totalPrice(0.0)
                    .remainingStock(cached.stock())
                    .status("FAILED")
                    .message("Insufficient stock in cache. Available: " + cached.stock())
                    .outputDestination("DB: external_order_log")
                    .build();
        }

        // 3. Decrement cached stock
        productCache.put(productId, new CachedProduct(
                cached.name(), cached.price(), cached.stock() - quantity));

        // 4. Build response
        double totalPrice = cached.price() * quantity;
        return FlashSaleResponse.builder()
                .workflow("EXTERNAL")
                .productName(cached.name())
                .requestedQuantity(quantity)
                .unitPrice(cached.price())
                .totalPrice(totalPrice)
                .remainingStock(cached.stock() - quantity)
                .status("SUCCESS")
                .message("Order processed from fallback cache (circuit breaker OPEN)")
                .outputDestination("DB: external_order_log")
                .build();
    }
}
