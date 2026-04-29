package com.flashsale.engine.service;

import com.flashsale.engine.model.Product;
import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.repository.ProductRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;

/**
 * Internal Workflow Service
 * -------------------------
 * The PRIMARY path — queries the real PostgreSQL DB for product details,
 * validates stock, decrements inventory.
 * Sink: appends order result to a single log file.
 *
 * This is the path used when the DB is healthy (circuit CLOSED).
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class InternalWorkflowService {

    private final ProductRepository productRepository;

    @Value("${flashsale.internal.output-dir:output/internal-orders}")
    private String outputDir;

    /**
     * Process an order against the real PostgreSQL database.
     * This method is called by the circuit breaker — if it throws,
     * the circuit breaker counts it as a failure.
     */
    @Transactional
    public FlashSaleResponse process(FlashSaleRequest request) {
        log.info("[INTERNAL] Processing order for productId={}", request.getProductId());

        // 1. Fetch product from DB
        Product product = productRepository.findById(request.getProductId())
                .orElseThrow(() -> new RuntimeException(
                        "Product not found with ID: " + request.getProductId()));

        // 2. Check stock availability
        if (product.getStockQuantity() < request.getQuantity()) {
            return FlashSaleResponse.builder()
                    .workflow("INTERNAL")
                    .productName(product.getName())
                    .requestedQuantity(request.getQuantity())
                    .unitPrice(product.getSalePrice())
                    .totalPrice(0.0)
                    .remainingStock(product.getStockQuantity())
                    .status("FAILED")
                    .message("Insufficient stock. Available: " + product.getStockQuantity())
                    .outputDestination("File: " + outputDir)
                    .build();
        }

        // 3. Decrement inventory
        product.setStockQuantity(product.getStockQuantity() - request.getQuantity());
        productRepository.save(product);

        // 4. Build and return response (sink write is deferred to orchestrator)
        double totalPrice = product.getSalePrice() * request.getQuantity();
        return FlashSaleResponse.builder()
                .workflow("INTERNAL")
                .productName(product.getName())
                .requestedQuantity(request.getQuantity())
                .unitPrice(product.getSalePrice())
                .totalPrice(totalPrice)
                .remainingStock(product.getStockQuantity())
                .status("SUCCESS")
                .message("Order processed from DB inventory")
                .outputDestination("File: " + outputDir)
                .build();
    }
}
